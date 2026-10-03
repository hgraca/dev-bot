#!/usr/bin/env bash
# src/agentic/aws/pre.sh
# Prerequisites check for AWS module.
# Run automatically by bin/install.sh and bin/update.sh.
#
# Classification (see the PDR on prerequisite reporting):
#   - curl/wget: manual, fatal — the AWS CLI cannot be downloaded without one.
#   - jq: optional — some verification steps are skipped without it.
#   - unzip, uv, mcp-proxy-for-aws-cli, aws: provisioned by this module's
#     install.sh/update.sh, so a missing one is a NOTICE before the first
#     install, never a failure.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

_main() {
  _header_3 "AWS prerequisites"

  # Manual and required: download the AWS CLI and the rules file.
  if command -v curl &>/dev/null; then
    _ok "curl (for downloading AWS CLI and rules)"
  elif command -v wget &>/dev/null; then
    _ok "wget (for downloading AWS CLI and rules)"
  else
    _error "Neither curl nor wget found — the AWS CLI cannot be downloaded; install one manually"
    return 1
  fi

  # Optional: only some verification steps use it.
  if command -v jq &>/dev/null; then
    _ok "jq (for parsing AWS responses)"
  else
    _info "jq not found — some AWS verification steps will be skipped"
  fi

  # Provisioned by this module's install.sh/update.sh.
  _prereq_module_installed unzip "unzip (required by the AWS CLI installer)"
  _prereq_module_installed uv "uv (required to install the AWS MCP proxy)"
  # Resolved through the launcher so this agrees with what a launch would do —
  # including the ~/.local/bin fallback when that is not on PATH.
  if bash "${MODULE_DIR}/tools/aws-mcp-proxy.sh" --which &>/dev/null; then
    _ok "${MCP_PROXY_PACKAGE} (AWS MCP server)"
  else
    _notice "${MCP_PROXY_PACKAGE} not found — 'devbot install'/'devbot update' will install it"
  fi
  _prereq_module_installed aws "aws CLI"
}

_main
