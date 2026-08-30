#!/usr/bin/env bash
# Update ollama — pull the latest Docker image and update all pulled models.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

main() {
  _info "ollama"

  # ── 1. Pull the ollama base image ──────────────────────────────────────
  _info "Pulling latest ollama/ollama image..."
  docker pull ollama/ollama:latest
  _ok "ollama image updated."

  # Note: Model updates are handled by each tools/module's update.sh
  # (continue, litellm, codebase-index, etc.) via _pull_ollama_models().
}

main
