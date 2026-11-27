#!/usr/bin/env bash
# src/agentic/kafka/pre.sh
# Prerequisites check for the kafka module.
# Run automatically by bin/install.sh and bin/update.sh.
#
# Classification (see the PDR on prerequisite reporting):
#   - node/npm: manual, fatal — the server cannot be installed without them.
#   - mcp-confluent: provisioned by this module's install.sh/update.sh, so a
#     missing one is a NOTICE before the first install, never a failure.
#
# GATE: Must work on Ubuntu, Fedora, and macOS.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

# The floor the package declares in its own engines field.
MIN_NODE_VERSION="22.23.4"

_main() {
  _header_3 "kafka prerequisites"

  local rc=0 node_version
  if command -v node >/dev/null 2>&1; then
    node_version="$(node -v 2>/dev/null || true)"
    node_version="${node_version#v}"
    if _kafka_version_ge "${node_version}" "${MIN_NODE_VERSION}"; then
      _ok "node ${node_version}"
    else
      _error "node ${node_version} is below the ${MIN_NODE_VERSION} floor ${MCP_PACKAGE} requires"
      rc=1
    fi
  else
    _error "node not found — ${MCP_PACKAGE} needs Node.js >= ${MIN_NODE_VERSION}; install Node manually"
    rc=1
  fi

  if command -v npm >/dev/null 2>&1; then
    _ok "npm"
  else
    _error "npm not found — ${MCP_PACKAGE} is installed with npm"
    rc=1
  fi

  # Resolved through the launcher so this agrees with what a launch would do,
  # including npm's global prefix when it is not on PATH.
  if bash "${MODULE_DIR}/tools/kafka-mcp-launch.sh" --which >/dev/null 2>&1; then
    _ok "${MCP_BINARY} (Kafka MCP server)"
  else
    _notice "${MCP_BINARY} not found — 'devbot install'/'devbot update' will install it"
  fi

  return "${rc}"
}

_main
