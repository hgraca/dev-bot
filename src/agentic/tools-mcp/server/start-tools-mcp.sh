#!/usr/bin/env bash
set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SERVER_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

if [[ -z "${TOOLS_MCP_PROJECT_DIR:-}" ]]; then
  SYMLINK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || SYMLINK_DIR="$(pwd)"
  TOOLS_MCP_PROJECT_DIR="$(cd "${SYMLINK_DIR}/.." 2>/dev/null && pwd)" || TOOLS_MCP_PROJECT_DIR="$(pwd)"
fi
export TOOLS_MCP_PROJECT_DIR

# Resolve bun robustly: opencode's MCP launch may not have ~/.bun/bin on PATH
# (a missing PATH makes `exec bun` fail with "bun: not found" at launch).
BUN="$(command -v bun 2>/dev/null || true)"
if [[ -z "${BUN}" && -x "${HOME}/.bun/bin/bun" ]]; then
  BUN="${HOME}/.bun/bin/bun"
fi
if [[ -z "${BUN}" ]]; then
  echo "bun not found — tools-mcp server unavailable (install via tools-mcp/install.sh)" >&2
  exit 1
fi

exec "${BUN}" run "${SERVER_DIR}/start-tools-mcp.ts"
