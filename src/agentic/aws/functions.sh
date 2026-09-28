#!/usr/bin/env bash
# src/agentic/aws/functions.sh
# Shared helpers — delegates to src/_shared/functions.sh for boilerplate.

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_shared/functions.sh
source "${MODULE_DIR}/../../_shared/functions.sh"

# The AWS MCP proxy runs as an installed uv tool, never resolved at launch:
# `uvx` re-resolves the whole dependency graph against PyPI on every start, and a
# single stalled request outruns the MCP client's 30 s init budget.
#
# `-cli` (not the bare library) is AWS's designated CLI artifact: it exact-pins
# the whole tree, so one version resolves identically on every machine.
MCP_PROXY_PACKAGE='mcp-proxy-for-aws-cli'
MCP_PROXY_VERSION='1.7.0'

# Install the pinned proxy as a uv tool. Idempotent: an exact-version match is
# skipped, so this is safe to call from both install.sh and update.sh.
_mcp_proxy_install() {
  local spec="${MCP_PROXY_PACKAGE}==${MCP_PROXY_VERSION}"
  # Capture before matching: under `pipefail`, `grep -q` exiting on the first
  # match sends SIGPIPE to uv, so a present tool would read as absent.
  local listed
  listed="$(uv tool list 2>/dev/null || true)"
  if grep -qE "^${MCP_PROXY_PACKAGE} v${MCP_PROXY_VERSION}$" <<<"${listed}"; then
    _skip "${MCP_PROXY_PACKAGE} (v${MCP_PROXY_VERSION})"
    return 0
  fi
  _info "Installing the AWS MCP proxy (${spec})..."
  if uv tool install "${spec}" 2>&1 | sed 's/^/  /'; then
    _ok "${MCP_PROXY_PACKAGE} installed"
    return 0
  fi
  _warn "Failed to install ${spec} — the AWS MCP server will not start until it is installed"
  return 1
}
