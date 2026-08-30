#!/usr/bin/env bash
# =============================================================================
# src/agentic/qmd/up.sh
# Runs on `devbot up`: shares qmd's downloaded llama models with ollama (via
# symlinked blobs + import under the qmd/ namespace) so ollama can serve them
# without re-downloading. No-op when ollama/docker/qmd models are unavailable.
# =============================================================================
set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

main() {
  _info "qmd"
  bash "${MODULE_DIR}/tools/share-with-ollama.sh"
}

main "$@"
