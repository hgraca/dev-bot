#!/usr/bin/env bash
# Install LiteLLM proxy — runs inside a Docker container, no host binary needed.
# Writes the default config; the image is pulled by docker compose on first use
# (install runs with `--all`, so pulling here would download 1.2 GB for a module
# that may never be enabled — `bin/up.sh` announces the pull when it happens).

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

  # ── Copy default config to project root ─────────────────────────────────
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
