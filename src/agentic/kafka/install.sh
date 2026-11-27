#!/usr/bin/env bash
# =============================================================================
# src/agentic/kafka/install.sh
# Install the MCP server the kafka module launches, at the pinned version.
#
# The server is an npm package installed globally, not resolved at launch: `npx`
# re-resolves the dependency graph on every start, and one stalled fetch outruns
# the MCP client's init budget (the same reason the aws module installs its proxy
# as a uv tool). The version comes from versions.env, which `devbot update` bumps.
#
# GATE: Must work on Ubuntu, Fedora, and macOS.
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

# The engine floor published by the package itself ("engines": {"node":
# ">=22.23.4"}). Below it the server refuses to start.
MIN_NODE_VERSION="22.23.4"

main() {
  _info "kafka — install ${MCP_PACKAGE}"

  if ! command -v node >/dev/null 2>&1; then
    _error "node not found — ${MCP_PACKAGE} needs Node.js >= ${MIN_NODE_VERSION}; install Node first"
    return 1
  fi
  if ! command -v npm >/dev/null 2>&1; then
    _error "npm not found — ${MCP_PACKAGE} is installed with npm; install Node.js >= ${MIN_NODE_VERSION} first"
    return 1
  fi

  local node_version
  node_version="$(node -v 2>/dev/null || true)"
  node_version="${node_version#v}"
  if ! _kafka_version_ge "${node_version}" "${MIN_NODE_VERSION}"; then
    _error "node ${node_version} is below the ${MIN_NODE_VERSION} floor ${MCP_PACKAGE} declares — upgrade Node first"
    return 1
  fi
  _ok "node ${node_version}"

  if _kafka_mcp_binary >/dev/null 2>&1 &&
    [[ "$("$(_kafka_mcp_binary)" --version 2>/dev/null || true)" == "${MCP_CONFLUENT_VERSION}" ]]; then
    _skip "${MCP_PACKAGE} ${MCP_CONFLUENT_VERSION} already installed"
    return 0
  fi

  if npm install -g "${MCP_PACKAGE}@${MCP_CONFLUENT_VERSION}" >/dev/null 2>&1; then
    _ok "${MCP_PACKAGE} ${MCP_CONFLUENT_VERSION} installed"
  else
    # Two very different causes, one message: the registry is unreachable, or
    # this Node has no prebuilt librdkafka binding (observed on 26.x).
    _error "npm install -g ${MCP_PACKAGE}@${MCP_CONFLUENT_VERSION} failed on node ${node_version} — check network / npm registry access; a very new Node may have no prebuilt librdkafka binding"
    return 1
  fi

  if ! _kafka_mcp_binary >/dev/null 2>&1; then
    _warn "${MCP_BINARY} is not on PATH after the install — npm's global bin directory may not be exported"
    return 1
  fi
}

main "$@"
