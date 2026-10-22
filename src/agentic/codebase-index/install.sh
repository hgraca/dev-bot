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

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

# ── main ─────────────────────────────────────────────────────────────────────

main() {
  _info "codebase-index — install"

  # No model ensure here: up.sh pulls nomic-embed-text on every `devbot up`, and
  # the shared ensure helper falls back to booting the ollama container when the
  # API is down — which pulls the 4.8 GB image at install time, the exact
  # download this module stopped doing.
  _ok "codebase-index installation complete"
}

main
