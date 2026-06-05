#!/usr/bin/env bash
# Install LiteLLM proxy — runs inside a Docker container, no host binary needed.
# Ensures the LiteLLM Docker image is pulled and config file is set up.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"

main() {
  echo
  _info "LiteLLM"

  # shellcheck source=./functions.sh
  source "${DEV_BOT_ROOT}/src/tools/litellm/functions.sh"

  # ── 1. Pull the Docker image ────────────────────────────────────────────
  if docker image inspect ghcr.io/berriai/litellm:main-latest &>/dev/null; then
    _skip "ghcr.io/berriai/litellm:main-latest image already pulled"
  else
    _info "Pulling LiteLLM Docker image..."
    docker pull ghcr.io/berriai/litellm:main-latest
    _ok "LiteLLM image pulled"
  fi

  # ── 3. Copy default config to project root ──────────────────────────────
  local config_src="${DEV_BOT_ROOT}/src/tools/litellm/config.yaml"
  local config_dst="${DEV_BOT_ROOT}/litellm.config.yaml"

  if [[ ! -f "${config_dst}" ]]; then
    if [[ -f "${config_src}" ]]; then
      _info "Copying default config to litellm.config.yaml..."
      cp "${config_src}" "${config_dst}"
      _ok "litellm.config.yaml created."
    else
      _skip "No default config.yaml found at src/tools/litellm/config.yaml"
    fi
  else
    _skip "litellm.config.yaml already exists — leaving unchanged."
  fi

  if [[ ${#LOCAL_MODELS[@]} -gt 0 ]]; then
    _info "Updating local models for litellm..."
    _pull_ollama_models "${LOCAL_MODELS[@]}"
  fi

  _ok "LiteLLM ready"
}

main
