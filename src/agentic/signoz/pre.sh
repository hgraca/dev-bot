#!/usr/bin/env bash
# src/agentic/signoz/pre.sh
# Prerequisites check for the SigNoz module.
# Run automatically by bin/install.sh and bin/update.sh.
#
# There is no per-machine binary any more: the MCP server runs as a shared
# machine-wide container (docker-compose.yml) and only the agent skills are
# fetched per machine (via npx). Docker is therefore the real prerequisite;
# curl is optional (it only powers the gateway readiness probe in up.sh).
#
# Non-destructive — warnings only for missing optional tools.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

_main() {
  local all_ok=true

  _header_3 "SigNoz prerequisites"

  # docker (required to run the shared MCP gateway container)
  if command -v docker >/dev/null 2>&1; then
    _ok "docker (for the shared MCP gateway container)"
  else
    _warn "docker not found — the SigNoz MCP gateway cannot run"
    all_ok=false
  fi

  # npx / node (required for installing agent skills)
  if command -v npx >/dev/null 2>&1; then
    _ok "npx (for installing agent skills)"
  else
    _warn "npx not found (node/npm required) — cannot install SigNoz agent skills"
    all_ok=false
  fi

  # curl (optional — the gateway readiness probe degrades gracefully without it)
  if command -v curl >/dev/null 2>&1; then
    _ok "curl (for the gateway readiness probe)"
  else
    _info "curl not found — gateway readiness probe will be skipped"
  fi

  if [[ "${all_ok}" == "false" ]]; then
    _warn "One or more prerequisites missing — install/update may be partial."
  fi
}

_main
