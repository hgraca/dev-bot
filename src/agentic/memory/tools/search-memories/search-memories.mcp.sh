#!/usr/bin/env bash
# ---
# description: Search the memory vault and return full file bodies. Fast keyword (BM25) search across QMD-indexed memories — no GPU or LLM models required.
# ---
# =============================================================================
# src/agentic/memory/tools/search-memories/search-memories.mcp.sh
# CLI wrapper for the search-memories tool — searches the memory vault and
# returns full file bodies to stdout.
#
# Usage:
#   devbot tool search-memories billing erp
#   devbot tool search-memories "planning workflow"
#   devbot tool search-memories billing erp --json
#   devbot tool search-memories billing --collection myproject --max-results 10
#
# Positional arguments are treated as search queries (one per word/phrase).
# Defaults:
#   --format: markdown (shell default; JS tool defaults to json)
#
# Parameters:
# - query (string, required): search query or JSON array string e.g. '["planning","workflow"]' or 'billing'
# - collection (string, optional): QMD collection name (default: auto-detected from devbot.jsonc)
# - max-results (number, optional): max files to return (default: 5)
# - format (string, optional): 'json' (default) or 'markdown'
# =============================================================================

set -euo pipefail

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"search-memories","description":"Search the memory vault and return full file bodies. Fast keyword (BM25) search across QMD-indexed memories — no GPU or LLM models required.","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"CLI args: <query> [--collection <name>] [--max-results <n>] [--json]"}},"required":["args"]}}
JSON
    exit 0
    ;;
esac

SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

TOOL_SCRIPT="${SCRIPT_DIR}/search-memories.py"

if [[ ! -f "${TOOL_SCRIPT}" ]]; then
  echo "FATAL: search-memories.py not found at ${TOOL_SCRIPT}" >&2
  exit 1
fi

# Parse args: positional args become --query values; flags pass through.
FORMAT="markdown"
HAS_FORMAT=false
QUERIES=()
EXTRA_ARGS=()
SKIP_NEXT=false

for i in "$@"; do
  # When previous arg was a two-token flag (--collection, --max-results, --format),
  # this value token belongs to that flag, not to QUERIES.
  if $SKIP_NEXT; then
    SKIP_NEXT=false
    EXTRA_ARGS+=("${i}")
    continue
  fi
  case "${i}" in
    --markdown)
      FORMAT="markdown"; HAS_FORMAT=true ;;
    --json)
      FORMAT="json"; HAS_FORMAT=true ;;
    --format|--collection|--max-results|--query)
      EXTRA_ARGS+=("${i}")
      SKIP_NEXT=true ;;
    --format=*)
      FORMAT="${i#--format=}"; HAS_FORMAT=true ;;
    --collection=*|--max-results=*|--query=*)
      EXTRA_ARGS+=("${i}") ;;
    --*)
      EXTRA_ARGS+=("${i}") ;;
    *)
      QUERIES+=("${i}") ;;
  esac
done

CMD=("python3" "${TOOL_SCRIPT}" "--format" "${FORMAT}")

for q in "${QUERIES[@]}"; do
  CMD+=("--query" "${q}")
done

CMD+=("${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}")

exec "${CMD[@]}"
