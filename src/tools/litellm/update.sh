#!/usr/bin/env bash
# Update LiteLLM — pull the latest Docker image.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

main() {
  _info "LiteLLM"

  _info "Pulling latest LiteLLM image..."
  docker pull ghcr.io/berriai/litellm:main-latest
  _ok "LiteLLM image updated."

  # ── Pull required ollama models ─────────────────────────────────────
  if [[ ${#LOCAL_MODELS[@]} -gt 0 ]]; then
    _info "Updating local models for litellm..."
    _pull_ollama_models "${LOCAL_MODELS[@]}"
  fi
}

main
