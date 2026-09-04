#!/usr/bin/env bash
# =============================================================================
# src/agentic/qmd/init.sh
# Set up QMD for a project: register collections, add context, build initial
# index.
#
# QMD is a local search engine for markdown files. This init script:
#   1. Checks qmd CLI is installed
#   2. Registers a project collection for <devbot-dir>/memory/latent/
#   3. Adds QMD context entries for agent guidance
#   4. Runs initial index + embedding
#
# Usage:
#   init.sh                         # init in current directory
#   init.sh /path/to/project        # init in specified project
#
# Adapted for dev-bot: self-contained, no external dependencies.
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

# ── Resolve paths ─────────────────────────────────────────────────────────────

PROJECT_DIR="$(cd "${1:-$(pwd)}" && pwd)"
PROJECT_NAME=""

# Resolve project name from .devbot.project.jsonc (matches search-memories.py),
# fall back to directory basename if config is missing or unreadable.
local_config="${PROJECT_DIR}/.devbot.project.jsonc"
if [[ -f "${local_config}" ]]; then
  PROJECT_NAME=$(python3 "${MODULE_DIR}/../../_shared/read_jsonc.py" "${local_config}" 2>/dev/null | jq -r '.project_name // ""' 2>/dev/null || echo "")
fi
PROJECT_NAME="${PROJECT_NAME:-$(basename "${PROJECT_DIR}")}"

# ── Cross-process llama serialization ─────────────────────────────────────────
# qmd update/embed load llama (GPU or CPU). Run concurrently from multiple
# processes (e.g. the cc + oc e2e containers sharing one GPU and a host-mounted
# model cache, or two reinit runs on one host) they contend for VRAM — and when
# GPU init fails qmd falls back to CPU, where llama uses every core (~100% CPU
# per process; two at once froze the host during dev-bot e2e runs). Serialize
# the llama-heavy index build with a cross-process flock on a file in the qmd
# cache root (XDG_CACHE_HOME/qmd — a host mount shared by the e2e containers),
# so only one llama run happens at a time. Bounded wait: if the lock is held
# longer than the embed timeout the other side is probably gone — proceed
# without it (warn) rather than hang init.
_acquire_qmd_llama_lock() {
  local lock_dir="${XDG_CACHE_HOME:-$HOME/.cache}/qmd"
  mkdir -p "${lock_dir}" 2>/dev/null || return 1
  exec 200>"${lock_dir}/.llama.lock" 2>/dev/null || return 1
  local waited=0 first_wait=1 cap="${QMD_EMBED_TIMEOUT:-180}"
  while ! { flock -n 200 2>/dev/null || python3 -c 'import fcntl; fcntl.flock(200, fcntl.LOCK_EX|fcntl.LOCK_NB)' 2>/dev/null; }; do
    if (( first_wait )); then
      first_wait=0
      _info "waiting for qmd llama lock (another reinit is embedding)…"
    fi
    waited=$((waited + 2))
    if (( waited >= cap )); then
      _warn "qmd llama lock held >${cap}s by another process — proceeding without it"
      return 1
    fi
    sleep 2
  done
  return 0
}

_release_qmd_llama_lock() {
  exec 200>&- 2>/dev/null || true
}

# ── Check qmd CLI ─────────────────────────────────────────────────────────────

_header_3 "QMD Init — ${PROJECT_NAME}"

if ! command -v qmd >/dev/null 2>&1; then
  _warn "qmd CLI not found — run install.sh first"
  exit 1
fi

_ok "qmd CLI: $(qmd --version 2>/dev/null || echo 'installed')"

# NOTE: no upfront `qmd doctor` — its device probe runs the llama backend on
# CPU and takes ~14 s in a GPU-less context, dwarfing the rest of init (the
# embed itself is ~1 s when embeddings are cached). GPU status is still
# reported from qmd's own embed output below.

# ── Check vault exists ────────────────────────────────────────────────────────

LATENT_DIR="${PROJECT_DIR}/$(_devbot_get_project_dir "${PROJECT_DIR}")/memory/latent"
if [[ ! -d "${LATENT_DIR}" ]]; then
  _warn "No latent memory directory found at:"
  echo "    ${LATENT_DIR}"
  echo "  Create it or ensure your project has the <devbot-dir>/memory/latent/ structure."
  echo "  Continuing with global collection only."
  HAS_LATENT=false
else
  HAS_LATENT=true
  _ok "Latent directory: ${LATENT_DIR}"
fi

# ── Register project collection ───────────────────────────────────────────────

if [[ "$HAS_LATENT" == "true" ]]; then
  _header_3 "Registering QMD collections"

  # Check if collection already exists (exact match, not substring)
  if qmd collection show "${PROJECT_NAME}" >/dev/null 2>&1; then
    _skip "Collection '${PROJECT_NAME}' already registered"
  else
    _info "Registering collection '${PROJECT_NAME}' for latent/..."
    qmd collection add "${LATENT_DIR}" \
      --name "${PROJECT_NAME}"
    _ok "Collection '${PROJECT_NAME}' registered"
  fi
fi

# ── Add QMD context ───────────────────────────────────────────────────────────

_header_3 "Adding QMD context"

CONTEXT_DESCRIPTION="Memory vault for ${PROJECT_NAME}: contains ADRs, PDRs, patterns, gotchas, project-level memories. Search this when you need to recall past decisions, find relevant patterns, or check if something was already documented."

if qmd context list 2>/dev/null | grep -qw "${PROJECT_NAME}"; then
  _skip "Context '${PROJECT_NAME}' already exists"
else
  qmd context add "qmd://${PROJECT_NAME}" "${CONTEXT_DESCRIPTION}" 2>/dev/null || true
  _ok "Context added for '${PROJECT_NAME}'"
fi

# Global collection context (collection created by memory module init.sh)
if qmd context list 2>/dev/null | grep -qw "dev-bot-global"; then
  _skip "Context 'dev-bot-global' already exists"
else
  qmd context add "qmd://dev-bot-global" "Global/shared knowledge across all projects" 2>/dev/null || true
  _ok "Context added for 'dev-bot-global'"
fi

# ── Build initial index ───────────────────────────────────────────────────────

_header_3 "Building QMD index"

# Serialize the llama-heavy build across processes sharing the qmd cache/GPU
# (see _acquire_qmd_llama_lock): concurrent reinit runs (cc + oc e2e) must not
# double-load llama and fall back to all-cores CPU embedding.
_LLAMA_LOCK_HELD=false
if _acquire_qmd_llama_lock; then
  _LLAMA_LOCK_HELD=true
fi

# Prune orphaned embedding chunks first (audit-26 NOTE-6): qmd status can
# report stale vectors from reindex churn (118 chunks / 12%). Best-effort —
# a cleanup failure must not block the index build (same pattern as the
# reindex-memories tool).
_info "Running qmd cleanup..."
if qmd cleanup 2>&1 | sed 's/^/  /'; then
  _ok "Orphaned chunks pruned"
else
  _warn "Cleanup had issues — continuing"
fi

_info "Running qmd update..."
if qmd update 2>&1 | sed 's/^/  /'; then
  _ok "Index updated"
else
  _warn "Index update had issues — continuing"
fi

_info "Running qmd embed..."
# Embedding needs a local model (llama) — without one it can hang downloading
# or connecting. Bound it with a timeout so a missing backend can't stall init;
# the warning below continues either way. Override with QMD_EMBED_TIMEOUT.
embed_status=0
embed_out="$(timeout "${QMD_EMBED_TIMEOUT:-180}" qmd embed 2>&1)" || embed_status=$?
echo "${embed_out}" | tail -5 | sed 's/^/  /'

# Report whether qmd is actually using the GPU (its own output is authoritative).
if echo "${embed_out}" | grep -qi "no GPU"; then
  _warn "QMD embeddings: CPU (no GPU acceleration)"
elif echo "${embed_out}" | grep -qiE "gpu"; then
  _ok "QMD embeddings: GPU"
else
  _info "QMD embeddings: GPU status not reported by qmd"
fi

if [[ ${embed_status} -ne 0 ]]; then
  _warn "Embedding had issues or timed out — continuing"
else
  _ok "Embedding complete"
fi

# Release the llama lock so a sibling process (other e2e container) can run its
# own build instead of waiting on us for the rest of this init.
if [[ "${_LLAMA_LOCK_HELD}" == "true" ]]; then
  _release_qmd_llama_lock
fi

_ok "QMD init complete for ${PROJECT_NAME}"
