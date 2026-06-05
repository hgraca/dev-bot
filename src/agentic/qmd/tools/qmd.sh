#!/usr/bin/env bash
# ---
# description: Search and navigate markdown knowledge bases using QMD. Supports query (semantic), search (BM25), get, multi-get, update, embed, and collection/context management.
# ---
# =============================================================================
# src/agentic/qmd/tools/qmd.sh
# CLI wrapper for the qmd (Quick Markdown) search tool.
# Passes all arguments through to the qmd CLI.
#
# Output format:
#
#   ## QMD output
#
#   ```
#   <output of the qmd command>
#   ```
#
# Usage:
#   qmd.sh status                  # Show QMD health and collections
#   qmd.sh query "question"        # Search with auto-expand + rerank
#   qmd.sh search "keywords"       # BM25-only search
#   qmd.sh get "#docid"            # Retrieve doc by ID
#   qmd.sh multi-get "glob"        # Retrieve multiple docs
#   qmd.sh update                  # Update index
#   qmd.sh embed                   # Run embedding
#   qmd.sh collection add ...      # Manage collections
#   qmd.sh context add ...         # Manage context entries
#   echo "query" | qmd.sh          # Pipe mode: stdin -> qmd
#   qmd.sh --help                  # Show usage
# =============================================================================

set -euo pipefail

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"qmd","description":"Search and navigate markdown knowledge bases using QMD. Supports query (semantic), search (BM25), get, multi-get, update, embed, and collection/context management.","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"QMD subcommand and arguments (e.g. status, query '<text>', search '<kw>', get '<id>')"}},"required":["args"]}}
JSON
    exit 0
    ;;
esac

# ── Help flag (check before qmd availability) ─────────────────────────────────

if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
  echo "Usage: qmd.sh [options] [command] [args...]"
  echo ""
  echo "CLI wrapper for the qmd (Quick Markdown) search tool."
  echo ""
  echo "Commands (forwarded to qmd CLI):"
  echo "  status          Show QMD health and collections"
  echo "  query <text>    Search with auto-expand + rerank"
  echo "  search <kw>     BM25-only keyword search"
  echo "  get <id>        Retrieve document by ID or path"
  echo "  multi-get <g>   Retrieve multiple documents by glob"
  echo "  update          Update the search index"
  echo "  embed           Run embedding model"
  echo "  collection      Manage collections (add, list, remove)"
  echo "  context         Manage context entries"
  echo ""
  echo "Pipe mode:"
  echo "  echo \"query\" | qmd.sh    Query from stdin"
  echo ""
  echo "Output:"
  echo "  ## QMD output"
  echo ""
  echo "  \`\`\`"
  echo "  <qmd result>"
  echo "  \`\`\`"
  exit 0
fi

# ── Check dependency ──────────────────────────────────────────────────────────

if ! command -v qmd &>/dev/null; then
  echo "Error: qmd CLI not found. Install with: npm install -g @tobilu/qmd" >&2
  exit 1
fi

# ── Pipe mode: no args + piped stdin ──────────────────────────────────────────

if [[ $# -eq 0 ]] && [[ ! -t 0 ]]; then
  INPUT=$(cat)
  OUTPUT=$(echo "$INPUT" | qmd 2>&1) || true
  echo "## QMD output"
  echo ""
  echo '```'
  echo "$OUTPUT"
  echo '```'
  exit 0
fi

# ── Normal mode: forward all args to qmd ──────────────────────────────────────

OUTPUT=$(qmd "$@" 2>&1) || true
echo "## QMD output"
echo ""
echo '```'
echo "$OUTPUT"
echo '```'
