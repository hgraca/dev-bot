#!/usr/bin/env bash
# ---
# description: Rebuild the memory index in the background (fire-and-forget) using the configured memory-search engine (qmd: cleanup && update, BM25-only; mdctx: incremental build of the project + global indexes). Coalesces concurrent runs via a pidfile. Pass the argument 'status' to check whether a reindex is running without launching one, or 'prune' to run the cheap self-heal for stale deleted-note entries.
# ---
# =============================================================================
# src/agentic/memory/tools/reindex-memories/reindex-memories.mcp.sh
# MCP/CLI shim for the memory reindex. The engine logic (provider dispatch,
# lock/coalesce, background + foreground modes, branch record) lives in
# tools/reindex-passive-memories.sh — the single source of truth shared by the
# harness hooks, this MCP tool, and search-memories' query-time --ensure.
#
# Only `mcp-meta` (the MCP discovery contract) is implemented here; every other
# argument is delegated verbatim:
#   reindex-memories.mcp.sh [status | prune]   →  reindex-passive-memories.sh ...
# =============================================================================

set -euo pipefail

# Resolve this script's real dir (tools are symlinked into .opencode/tools).
SOURCE="${BASH_SOURCE[0]}"
while [[ -L "${SOURCE}" ]]; do
  DIR="$(cd -P "$(dirname "${SOURCE}")" && pwd)"
  SOURCE="$(readlink "${SOURCE}")"
  [[ "${SOURCE}" != /* ]] && SOURCE="${DIR}/${SOURCE}"
done
SCRIPT_DIR="$(cd -P "$(dirname "${SOURCE}")" && pwd)"

CANONICAL="${SCRIPT_DIR}/../reindex-passive-memories.sh"

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"reindex-memories","description":"Rebuild the memory index in the background (fire-and-forget) using the configured memory-search engine (qmd: cleanup && update, BM25-only; mdctx: incremental build of the project + global indexes). Coalesces concurrent runs via a pidfile. Pass the argument 'status' to check whether a reindex is running without launching one, or 'prune' to run the cheap self-heal for stale deleted-note entries.","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"Optional positional: 'status' to report running/idle without launching; 'prune' to launch the cheap self-heal pass"}}}}
JSON
    exit 0
    ;;
esac

if [[ ! -f "${CANONICAL}" ]]; then
  printf 'FATAL: memory reindex engine not found at %s\n' "${CANONICAL}" >&2
  exit 1
fi

exec bash "${CANONICAL}" "$@"
