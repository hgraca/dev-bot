#!/usr/bin/env bash
# src/agentic/signoz/pre.sh
# Prerequisites check for the SigNoz module.
# Run automatically by bin/install.sh and bin/update.sh.
#
# Classification (see the PDR on prerequisite reporting):
#   - docker: manual, fatal — the shared MCP gateway runs as a container.
#   - npx: manual, fatal — node/npm is not provisioned by this module.
#   - curl: optional — only powers the gateway readiness probe.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

_main() {
  _header_3 "SigNoz prerequisites"

  # Manual and required.
  _prereq_manual docker "docker (for the shared MCP gateway container)"
  _prereq_manual npx "npx (for installing agent skills)"

  # Optional.
  if command -v curl &>/dev/null; then
    _ok "curl (for the gateway readiness probe)"
  else
    _info "curl not found — gateway readiness probe will be skipped"
  fi
}

_main
