#!/usr/bin/env bash
# =============================================================================
# src/agentic/qmd/tools/share-with-ollama.sh
# Share qmd's downloaded llama models with ollama so ollama can serve them
# WITHOUT re-downloading AND without duplicating the bytes on disk.
#
# How it works, per GGUF in qmd's model cache:
#   1. `ollama create qmd/<name>:<quant>` with a Modelfile FROM the mounted
#      GGUF (/root/.qmd-cache, read-only — added by the ollama docker-compose).
#      Ollama materializes its blob copy (or dedups an existing one) — this
#      step must see a writable blob path, which is why we do NOT pre-link.
#   2. Replace the materialized blob with a symlink to qmd's GGUF
#      (blobs/sha256-<hash> → /root/.qmd-cache/<file>). This frees the copy —
#      the blob "file" IS the qmd GGUF — verified serving reads straight
#      through the symlink. Net effect: zero download, zero extra SSD bytes.
#
# Why not symlink BEFORE create: ollama 0.30.6's `create` always materializes
# the GGUF layer — with a read-only target (symlink or ro bind mount) it fails
# EROFS on the write. Creating first, then relinking, sidesteps that.
#
# The `qmd/` namespace marks the models as QMD-sourced: `ollama list` shows
# them clearly, and `ollama rm` removes only the manifest + blob symlink —
# qmd's cache files are never touched.
#
# Idempotent: skips models already imported. Recreates the ollama container
# when its /root/.qmd-cache mount is missing OR stale (bin/up.sh uses
# --no-recreate, so a replaced host cache dir needs a forced recreate).
# Called by qmd/up.sh on `devbot up`; can also be invoked directly.
#
# GATE: This module must work on Ubuntu, Fedora, and macOS.
# =============================================================================
set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../functions.sh
source "${MODULE_DIR}/functions.sh"

QMD_CACHE_DIR="${QMD_MODELS_DIR:-$HOME/.cache/qmd/models}"
OLLAMA_COMPOSE="${DEV_BOT_ROOT}/src/tools/ollama/docker-compose.yml"
CONTAINER="dev-bot-ollama"
CACHE_MOUNT="/root/.qmd-cache"
OLLAMA_HOME="/root/.ollama"

# "model-name:gguf-filename:quant"
MODELS=(
  "embeddinggemma-300m:hf_ggml-org_embeddinggemma-300M-Q8_0.gguf:q8_0"
  "qmd-query-expansion-1.7b:hf_tobil_qmd-query-expansion-1.7B-q4_k_m.gguf:q4_k_m"
  "qwen3-reranker-0.6b:hf_ggml-org_qwen3-reranker-0.6b-q8_0.gguf:q8_0"
)

_mount_is_stale() {
  # Host has a downloaded GGUF the container's /root/.qmd-cache cannot see —
  # the bind is pinned to a replaced host directory (docker keeps the source
  # inode across plain `up`, so only a forced recreate re-resolves it).
  # This is the failure behind ollama's misleading "400 invalid model name":
  # `ollama create` cannot open the FROM path and falls back to name parsing.
  local entry file
  for entry in "${MODELS[@]}"; do
    file="${entry#*:}"; file="${file%%:*}"
    [[ -f "${QMD_CACHE_DIR}/${file}" ]] || continue
    if ! docker exec "${CONTAINER}" test -f "${CACHE_MOUNT}/${file}" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

_recreate_ollama_container() {
  _info "recreating ${CONTAINER} ${1:-to fix the qmd cache mount}..."
  # Mirror bin/up.sh's compose opts — append docker-compose.gpu.yml when
  # gpu_enabled, or the recreation would drop the GPU passthrough (ollama then
  # serves embeddings CPU-only).
  local -a compose_opts=("-f" "${OLLAMA_COMPOSE}")
  if _devbot_is_true "gpu_enabled"; then
    compose_opts+=("-f" "${DEV_BOT_ROOT}/docker-compose.gpu.yml")
  fi
  # --force-recreate is required: a stale mount leaves the compose spec
  # identical to the running container, so plain `up -d` would be a no-op.
  docker compose "${compose_opts[@]}" up -d --force-recreate ollama
}

_wait_for_ollama() {
  # A freshly recreated container needs a moment before ollama serves; the
  # import loop's first `ollama list`/`ollama create` must not race it.
  local tries=0
  while ! docker exec "${CONTAINER}" ollama list >/dev/null 2>&1; do
    tries=$((tries + 1))
    if [[ "${tries}" -ge 15 ]]; then
      _warn "ollama not responding after recreate (15s) — continuing"
      return 0
    fi
    sleep 1
  done
}

_ensure_qmd_cache_mount() {
  # Recreate when the mount is missing (container predates the compose mount)
  # or stale (bind pinned to a replaced host dir — an empty mount that a plain
  # `test -d` cannot detect). Fails loudly if the mount still will not heal.
  if ! docker exec "${CONTAINER}" sh -c "test -d ${CACHE_MOUNT}" 2>/dev/null; then
    _recreate_ollama_container "to add the qmd cache mount"
    _wait_for_ollama
    return 0
  fi
  if _mount_is_stale; then
    _recreate_ollama_container "to re-resolve the qmd cache mount"
    _wait_for_ollama
    if _mount_is_stale; then
      _error "qmd cache mount still stale after recreate — is ${QMD_CACHE_DIR} intact?"
      return 1
    fi
    _ok "qmd cache mount re-resolved"
  fi
}

main() {
  _info "qmd → ollama model share"

  if ! docker info >/dev/null 2>&1; then
    _skip "no docker daemon — ollama import skipped"
    return 0
  fi
  if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "${CONTAINER}"; then
    _warn "${CONTAINER} not running — start it first (devbot up)"
    return 0
  fi
  if [[ ! -d "${QMD_CACHE_DIR}" ]]; then
    _skip "qmd model cache not found at ${QMD_CACHE_DIR} — run 'qmd pull' first"
    return 0
  fi

  _ensure_qmd_cache_mount

  local entry name file quant gguf sha blob imported
  for entry in "${MODELS[@]}"; do
    name="${entry%%:*}"
    file="${entry#*:}"; file="${file%%:*}"
    quant="${entry##*:}"
    gguf="${QMD_CACHE_DIR}/${file}"
    if [[ ! -f "${gguf}" ]]; then
      _skip "qmd model ${file} not downloaded yet — skipping (run 'qmd pull')"
      continue
    fi

    imported="$(docker exec "${CONTAINER}" ollama list 2>/dev/null | awk '{print $1}' | grep -c "^qmd/${name}:${quant}$" || true)"
    if [[ "${imported}" -gt 0 ]]; then
      _skip "qmd/${name}:${quant} already imported"
      continue
    fi

    sha="$(sha256sum "${gguf}" | cut -d' ' -f1)"
    blob="${OLLAMA_HOME}/models/blobs/sha256-${sha}"

    # 1. Import. FROM is the mounted GGUF (a regular file in the container's
    #    view). A stale symlink at the blob path must go first — ollama needs
    #    a writable blob path while it materializes the layer.
    if docker exec "${CONTAINER}" test -L "${blob}" 2>/dev/null; then
      _info "removing stale blob symlink..."
      docker exec "${CONTAINER}" rm -f "${blob}"
    fi
    _info "importing qmd/${name}:${quant} into ollama..."
    docker exec "${CONTAINER}" sh -c "printf 'FROM ${CACHE_MOUNT}/${file}\n' > /tmp/qmd-share.Modelfile && ollama create qmd/${name}:${quant} -f /tmp/qmd-share.Modelfile; rc=\$?; rm -f /tmp/qmd-share.Modelfile; exit \$rc" \
      | sed 's/^/  /'

    # 2. Replace the materialized blob copy with a symlink to qmd's GGUF —
    #    frees the copy; serving reads straight through the symlink.
    docker exec "${CONTAINER}" sh -c "rm -f ${blob} && ln -s ${CACHE_MOUNT}/${file} ${blob}"
    _ok "qmd/${name}:${quant} available in ollama (blob symlinks to qmd's cache — no download, no duplicate bytes)"
  done
}

main "$@"
