#!/usr/bin/env bash
# Install codebase-index module dependencies and hooks.
# - Verifies python3
# - Registers MCP server config
# - Git hooks are handled by init.sh (per-project setup)
#
# Config file (.opencode/codebase-index.json) is handled per-project by init.sh.
# Ollama model pull is handled by up.sh (run on `devbot up`).
#
# GATE: This module must work on Ubuntu, Fedora, and macOS.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

# ── main ─────────────────────────────────────────────────────────────────────

main() {
  _info "codebase-index — install"

  PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

  if [[ ${#LOCAL_MODELS[@]} -gt 0 ]]; then
    _info "Pulling ollama models for codebase-index..."
    _pull_ollama_models "${LOCAL_MODELS[@]}"
  fi

  _ok "codebase-index installation complete"
}

main
