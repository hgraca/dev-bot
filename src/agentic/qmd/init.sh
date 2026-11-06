#!/usr/bin/env bash
# =============================================================================
# src/agentic/qmd/init.sh
# Set up QMD for a project: register collections, add context, build initial
# index.
#
# QMD is a local search engine for markdown files, used BM25-only through the
# memory module — no model download, no embeddings (see ADR
# ADRs/20260913072905-qmd-bm25-only-no-model-downloads). This init script:
#   1. Checks qmd CLI is installed
#   2. Registers a project collection for <devbot-dir>/memory/
#   3. Adds QMD context entries for agent guidance
#   4. Runs the initial BM25 index (cleanup + update)
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
PROJECT_NAME="$(_devbot_memory_collection_field "${PROJECT_DIR}" project physical)"

if [[ -z "${PROJECT_NAME}" ]]; then
  # Resolve project name from .devbot.project.jsonc (matches search-memories.py),
  # fall back to directory basename if config is missing or unreadable.
  local_config="${PROJECT_DIR}/.devbot.project.jsonc"
  if [[ -f "${local_config}" ]]; then
    PROJECT_NAME=$(python3 "${MODULE_DIR}/../../_shared/read_jsonc.py" "${local_config}" 2>/dev/null | jq -r '.project_name // ""' 2>/dev/null || echo "")
  fi
fi
PROJECT_NAME="${PROJECT_NAME:-$(basename "${PROJECT_DIR}")}"

# ── Check qmd CLI ─────────────────────────────────────────────────────────────

_header_3 "QMD Init — ${PROJECT_NAME}"

if ! command -v qmd >/dev/null 2>&1; then
  _warn "qmd CLI not found — run install.sh first"
  exit 1
fi

_ok "qmd CLI: $(qmd --version 2>/dev/null || echo 'installed')"

# ── Check vault exists ────────────────────────────────────────────────────────

DEVBOT_DIR="$(_devbot_get_project_dir "${PROJECT_DIR}")"
CONVENTIONAL_MEMORY="${PROJECT_DIR}/${DEVBOT_DIR}/memory/latent"
LEGACY_MEMORY_ROOT="${PROJECT_DIR}/${DEVBOT_DIR}/memory"
MEMORY_DIR="$(_devbot_memory_collection_field "${PROJECT_DIR}" project path)"
[[ -n "${MEMORY_DIR}" ]] || MEMORY_DIR="${CONVENTIONAL_MEMORY}"
if [[ ! -d "${MEMORY_DIR}" && "${MEMORY_DIR}" == "${CONVENTIONAL_MEMORY}" ]]; then
  mkdir -p "${MEMORY_DIR}" 2>/dev/null || true
fi
if [[ ! -d "${MEMORY_DIR}" ]]; then
  # A surviving whole-memory registration would keep work/thinking searchable
  # while the resolver points at the missing latent path: refuse to leave it.
  if qmd collection show "${PROJECT_NAME}" >/dev/null 2>&1; then
    _error "Collection '${PROJECT_NAME}' is registered but ${MEMORY_DIR} is missing; refusing to leave a whole-memory collection active"
    exit 1
  fi
  _warn "No memory directory found at:"
  echo "    ${MEMORY_DIR}"
  echo "  Create it or ensure your project has the <devbot-dir>/memory/latent/ structure."
  echo "  Continuing with global collection only."
  HAS_MEMORY=false
else
  HAS_MEMORY=true
  _ok "Memory directory: ${MEMORY_DIR}"
fi

# ── Register project collection ───────────────────────────────────────────────

# The last successful build records the project collection root it registered.
# A changed external root is a legitimate migration when it matches; anything
# else at the same name belongs to another checkout.
_persist_project_collection_path() {
  local path="$1"
  local record="${PROJECT_DIR}/${DEVBOT_DIR}/logs/memory-index-branch.json"
  mkdir -p "$(dirname "${record}")" 2>/dev/null || true
  python3 - "${record}" "${path}" <<'PY'
import json
import os
import sys

record, path = sys.argv[1], sys.argv[2]
try:
    data = json.load(open(record))
except Exception:
    data = {}
data["project_collection_path"] = path
tmp = f"{record}.tmp.{os.getpid()}"
with open(tmp, "w") as handle:
    json.dump(data, handle)
os.replace(tmp, record)
PY
}

previous_path=""
record="${PROJECT_DIR}/${DEVBOT_DIR}/logs/memory-index-branch.json"
if [[ -f "${record}" ]]; then
  previous_path="$(python3 - "${record}" <<'PY'
import json
import sys

try:
    print(json.load(open(sys.argv[1])).get("project_collection_path", ""))
except Exception:
    pass
PY
)"
fi

if [[ "$HAS_MEMORY" == "true" ]]; then
  _header_3 "Registering QMD collections"

  # Check if collection already exists (exact match, not substring). An
  # existing collection may still be rooted at the whole-memory scope from
  # before latent-only indexing; migrate it so work/ and thinking/ notes drop
  # out of search results.
  released=""
  if qmd collection show "${PROJECT_NAME}" >/dev/null 2>&1; then
    current_path="$(qmd collection show "${PROJECT_NAME}" 2>/dev/null | awk '/^[[:space:]]*Path:/{sub(/^[[:space:]]*Path:[[:space:]]*/, ""); print; exit}')"
    if [[ -z "${current_path}" ]]; then
      _warn "Could not determine the root of collection '${PROJECT_NAME}'"
      exit 1
    elif [[ "${current_path}" != "${MEMORY_DIR}" ]]; then
      if [[ "${current_path}" != "${LEGACY_MEMORY_ROOT}" ]]; then
        # Only a root recorded by this checkout's last successful build is a
        # legitimate former override. A nested worktree is a descendant of
        # PROJECT_DIR but has its own record, so a prefix check would let the
        # main checkout steal the worktree's registration.
        if [[ -z "${previous_path}" || "${current_path}" != "${previous_path}" ]]; then
          _error "Collection '${PROJECT_NAME}' is registered at ${current_path}, not this checkout's ${MEMORY_DIR} (name collision); refusing to repoint"
          exit 1
        fi
      fi
      _info "Migrating collection '${PROJECT_NAME}' from ${current_path} to ${MEMORY_DIR}..."
      released="$(_devbot_release_custom_at_path "${MEMORY_DIR}")"
      if ! qmd collection remove "${PROJECT_NAME}" >/dev/null 2>&1; then
        _devbot_restore_custom_at_path "${released}" "${MEMORY_DIR}"
        _warn "Could not remove the old collection '${PROJECT_NAME}'"
        exit 1
      fi
      if qmd collection add "${MEMORY_DIR}" --name "${PROJECT_NAME}"; then
        if ! migrated_path="$(qmd collection show "${PROJECT_NAME}" 2>/dev/null | awk '/^[[:space:]]*Path:/{sub(/^[[:space:]]*Path:[[:space:]]*/, ""); print; exit}')"; then
          migrated_path=""
        fi
      else
        migrated_path=""
      fi
      if [[ "${migrated_path}" == "${MEMORY_DIR}" ]]; then
        _ok "Collection '${PROJECT_NAME}' migrated"
      else
        _warn "Could not migrate collection '${PROJECT_NAME}'"
        qmd collection remove "${PROJECT_NAME}" >/dev/null 2>&1 || true
        qmd collection add "${current_path}" --name "${PROJECT_NAME}" >/dev/null 2>&1 || true
        _devbot_restore_custom_at_path "${released}" "${MEMORY_DIR}"
        exit 1
      fi
    else
      _skip "Collection '${PROJECT_NAME}' already registered"
    fi
  else
    _info "Registering collection '${PROJECT_NAME}' for the latent corpus..."
    released="$(_devbot_release_custom_at_path "${MEMORY_DIR}")"
    if ! qmd collection add "${MEMORY_DIR}" --name "${PROJECT_NAME}"; then
      _devbot_restore_custom_at_path "${released}" "${MEMORY_DIR}"
      _warn "Could not register collection '${PROJECT_NAME}'"
      exit 1
    fi
    _ok "Collection '${PROJECT_NAME}' registered"
  fi
  # Record ownership for the next init/reindex. A record without the index
  # fingerprints is still stale, so this never marks an unbuilt index fresh.
  _persist_project_collection_path "${MEMORY_DIR}"
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

# BM25-only: `cleanup` prunes stale chunks, `update` rebuilds the index. No
# model is loaded, so there is no llama serialization lock and no embed step
# (see ADR 20260913072905-qmd-bm25-only-no-model-downloads).

# Prune orphaned chunks first (audit-26 NOTE-6): qmd status can report stale
# entries from reindex churn. Best-effort — a cleanup failure must not block
# the index build (same pattern as the reindex-memories tool).
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

_ok "QMD init complete for ${PROJECT_NAME}"
