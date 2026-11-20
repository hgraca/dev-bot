#!/usr/bin/env bash
# src/agentic/aws/update.sh
# Update the AWS CLI and uv to the latest versions, keep the pinned AWS MCP proxy
# installed, and refresh the AWS agent rules at upstream main's current commit,
# moving the pin only once that fetch has landed. Skills update separately via
# the external-modules module during `devbot update`.
#
# GATE: This module must work on Ubuntu, Fedora, and macOS.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "${MODULE_DIR}/../../.." && pwd)}"

AWS_CLI_INSTALLER='https://awscli.amazonaws.com/v2/install.sh'


main() {
  _info "aws — update"

  # uv
  if command -v uv &>/dev/null; then
    _info "Updating uv..."
    uv self update 2>&1 | sed 's/^/  /' || _warn "uv self update failed"
    # Keep the pinned AWS MCP proxy installed (uv tool, never resolved at launch).
    _mcp_proxy_install || true
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

  # Rules: one locked transaction — fetch the candidate and move the pin
  # together, so no update can interleave and no failure splits the pair.
  local latest="" rules_ok=1
  latest="$(_aws_rules_upstream_ref)"
  if [[ -n "${latest}" ]]; then
    _aws_rules_refresh "${latest}" || rules_ok=0
  else
    _warn "git ls-remote failed (offline?) — refreshing at the current pin"
    _aws_fetch_rules || rules_ok=0
  fi

  if (( rules_ok )); then
    _ok "aws update complete"
  else
    _warn "aws update incomplete — the AWS CLI and proxy updated, the rules did not"
  fi
}

main "$@"
