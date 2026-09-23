#!/usr/bin/env bash
# ---
# description: Deterministic, agent-callable refactoring for PHP — rename a method, class, static method or property and update every genuine reference. Dry-run by default; pass --apply to write.
# ---
# =============================================================================
# src/agentic/refactor/tools/refactor/refactor.mcp.sh
# Thin CLI wrapper for the refactor tool — delegates to refactor.ts via bun.
#
# Usage:
#   refactor.mcp.sh --op rename-method --class <FQCN> --method <old> --to <new>
#   refactor.mcp.sh --op rename-class --class <FQCN> --to <new> --apply
#   refactor.mcp.sh --help
#
# Dependencies: bun (installed by the tools-mcp module)
# =============================================================================

set -euo pipefail

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"refactor","description":"Deterministic, agent-callable refactoring for PHP — rename a method, class, static method or property and update every genuine reference. Dry-run by default; pass --apply to write.","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"CLI args: --op <rename-method|rename-class|rename-static-method|rename-property> [--class <FQCN>] [--method <old>|--property <old>] --to <new> [--apply] [--json] [--force]"}},"required":["args"]}}
JSON
    exit 0
    ;;
esac

# Resolve through symlinks — the tool is farmed into .agents/tools/. No
# `readlink -f`: GNU-only, and this module must run on macOS too.
SOURCE="${BASH_SOURCE[0]}"
while [[ -L "${SOURCE}" ]]; do
  DIR="$(cd -P "$(dirname "${SOURCE}")" && pwd)"
  SOURCE="$(readlink "${SOURCE}")"
  [[ "${SOURCE}" != /* ]] && SOURCE="${DIR}/${SOURCE}"
done
SCRIPT_DIR="$(cd -P "$(dirname "${SOURCE}")" && pwd)"

# Resolve bun robustly: the MCP launch may not have ~/.bun/bin on PATH (a
# missing PATH makes `exec bun` fail with "bun: not found" at launch).
BUN="$(command -v bun 2>/dev/null || true)"
if [[ -z "${BUN}" && -x "${HOME}/.bun/bin/bun" ]]; then
  BUN="${HOME}/.bun/bin/bun"
fi
if [[ -z "${BUN}" ]]; then
  echo "ERROR: bun not found — the tools-mcp module installs it" >&2
  exit 1
fi

exec "${BUN}" run "${SCRIPT_DIR}/refactor.ts" "$@"
