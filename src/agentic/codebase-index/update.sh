#!/usr/bin/env bash
# Update codebase-index module — rebuilds any missing or stale indices.
# Ollama model pull is handled by up.sh (run on `devbot up`).
#
# GATE: This module must work on Ubuntu, Fedora, and macOS.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

# ── main ─────────────────────────────────────────────────────────────────────

main() {
  _info "codebase-index — update"
  _check_python3

  if [[ ${#LOCAL_MODELS[@]} -gt 0 ]]; then
    _info "Ensuring local models for codebase-index..."
    _ensure_ollama_models_detached "${LOCAL_MODELS[@]}"
  fi

  _ok "codebase-index update complete"
}

main "$@"
