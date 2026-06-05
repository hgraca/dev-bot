#!/usr/bin/env bash
# =============================================================================
# src/tools/litellm/up.sh
# Pulls the qwen2.5-coder:7b model for LiteLLM proxied Ollama access.
# Runs on `devbot up` — after docker services (including Ollama) are started.
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

OLLAMA_API="${OLLAMA_LOCAL_API:-http://localhost:18434}"

main() {
  _info "litellm — up"

  if [[ ${#LOCAL_MODELS[@]} -gt 0 ]]; then
    _info "Pulling local models for litellm..."
    _pull_ollama_models "${LOCAL_MODELS[@]}"
  fi

  _ok "litellm up complete"
}

main "$@"
