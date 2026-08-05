#!/usr/bin/env bash
set -euo pipefail

RESOLVED="$(readlink -f "${BASH_SOURCE[0]}")"
SERVER_DIR="$(cd "$(dirname "${RESOLVED}")" && pwd)"

if [[ -z "${TOOLS_MCP_PROJECT_DIR:-}" ]]; then
  SYMLINK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || SYMLINK_DIR="$(pwd)"
  TOOLS_MCP_PROJECT_DIR="$(cd "${SYMLINK_DIR}/.." 2>/dev/null && pwd)" || TOOLS_MCP_PROJECT_DIR="$(pwd)"
fi
export TOOLS_MCP_PROJECT_DIR

exec bun run "${SERVER_DIR}/start-tools-mcp.ts"
