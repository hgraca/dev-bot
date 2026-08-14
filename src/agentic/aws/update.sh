#!/usr/bin/env bash
# src/agentic/aws/update.sh
# Update the AWS CLI and uv to the latest versions, and refresh the AWS agent
# rules in storage. Skills update separately via the external-modules module
# during `devbot update`.
#
# GATE: This module must work on Ubuntu, Fedora, and macOS.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "${MODULE_DIR}/../../.." && pwd)}"

AWS_CLI_INSTALLER='https://awscli.amazonaws.com/v2/install.sh'
RULES_URL='https://raw.githubusercontent.com/aws/agent-toolkit-for-aws/refs/heads/main/rules/aws-agent-rules.md'
RULES_DIR="${DEV_BOT_ROOT}/storage/aws/rules"

main() {
  _info "aws — update"

  # uv
  if command -v uv &>/dev/null; then
    _info "Updating uv..."
    uv self update 2>&1 | sed 's/^/  /' || _warn "uv self update failed"
  else
    _warn "uv not installed — run install.sh"
  fi

  # AWS CLI
  if command -v aws &>/dev/null; then
    _info "Updating AWS CLI..."
    if ! curl -fsSL "${AWS_CLI_INSTALLER}" | bash 2>&1 | sed 's/^/  /'; then
      _warn "AWS CLI update failed"
    fi
  else
    _warn "aws CLI not installed — run install.sh"
  fi

  # Rules
  mkdir -p "${RULES_DIR}"
  if curl -fsSL "${RULES_URL}" -o "${RULES_DIR}/aws-agent-rules.md"; then
    _ok "Refreshed ${RULES_DIR}/aws-agent-rules.md"
  else
    _warn "Failed to refresh rules from ${RULES_URL}"
  fi

  _ok "aws update complete"
}

main "$@"
