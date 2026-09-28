#!/usr/bin/env bash
# src/agentic/aws/pre.sh
# Prerequisites check for AWS module.
# Run automatically by bin/install.sh and bin/update.sh.
#
# Checks: curl (or wget), jq, unzip, uv, mcp-proxy-for-aws-cli, aws.
# Non-destructive — warnings only for missing optional tools.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

_main() {
  local all_ok=true

  _header_3 "AWS prerequisites"

  # curl or wget (required for downloading the AWS CLI and rules file)
  if command -v curl &>/dev/null; then
    _ok "curl (for downloading AWS CLI and rules)"
  elif command -v wget &>/dev/null; then
    _ok "wget (for downloading AWS CLI and rules)"
  else
    _warn "Neither curl nor wget found — cannot download AWS CLI"
    all_ok=false
  fi

  # jq (used to parse AWS responses in scripts)
  if command -v jq &>/dev/null; then
    _ok "jq (for parsing AWS responses)"
  else
    _warn "jq not found — some AWS verification steps may be skipped"
    all_ok=false
  fi

  # unzip (required by the AWS CLI installer on Linux)
  if command -v unzip &>/dev/null; then
    _ok "unzip (required by AWS CLI installer on Linux)"
  else
    _warn "unzip not found — AWS CLI installer needs it on Linux"
    all_ok=false
  fi

  # uv (required to install the AWS MCP proxy as a uv tool)
  if command -v uv &>/dev/null; then
    _ok "uv (required to install the AWS MCP proxy)"
  else
    _warn "uv not found — the AWS MCP proxy cannot be installed"
    all_ok=false
  fi

  # mcp-proxy-for-aws-cli (the AWS MCP server, installed as a uv tool)
  # Resolved through the launcher so this agrees with what a launch would do —
  # including the ~/.local/bin fallback when that is not on PATH.
  if bash "${MODULE_DIR}/tools/aws-mcp-proxy.sh" --which &>/dev/null; then
    _ok "${MCP_PROXY_PACKAGE} (AWS MCP server)"
  else
    _warn "${MCP_PROXY_PACKAGE} not found — AWS MCP server will not run (run install.sh / update.sh)"
    all_ok=false
  fi

  # aws CLI (installed by install.sh)
  if command -v aws &>/dev/null; then
    _ok "aws ($(aws --version 2>&1 | head -1))"
  else
    _warn "aws CLI not found — run install.sh"
    all_ok=false
  fi

  if [[ "${all_ok}" == "false" ]]; then
    _warn "One or more prerequisites missing — install/update may be partial."
  fi
}

_main
