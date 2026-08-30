#!/usr/bin/env bash
# src/agentic/signoz/pre.sh
# Prerequisites check for SigNoz module.
# Run automatically by bin/install.sh and bin/update.sh.
#
# Checks: curl (or wget), tar, npx (node), uname (always available).
# Non-destructive — warnings only for missing optional tools.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

_main() {
  local all_ok=true

  _header_3 "SigNoz prerequisites"

  # curl or wget (required for downloading binary)
  if command -v curl >/dev/null 2>&1; then
    _ok "curl (for downloading binary)"
  elif command -v wget >/dev/null 2>&1; then
    _ok "wget (for downloading binary)"
  else
    _warn "Neither curl nor wget found — cannot download SigNoz MCP binary"
    all_ok=false
  fi

  # tar (required to extract archive)
  if command -v tar >/dev/null 2>&1; then
    _ok "tar (for extracting archive)"
  else
    _warn "tar not found — cannot extract SigNoz MCP binary"
    all_ok=false
  fi

  # npx / node (required for installing skills)
  if command -v npx >/dev/null 2>&1; then
    _ok "npx (for installing agent skills)"
  else
    _warn "npx not found (node/npm required) — cannot install SigNoz agent skills"
    all_ok=false
  fi

  if [[ "${all_ok}" == "false" ]]; then
    _warn "One or more prerequisites missing — install/update may be partial."
  fi
}

_main
