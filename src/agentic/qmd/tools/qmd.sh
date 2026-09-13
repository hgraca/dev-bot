#!/usr/bin/env bash
# =============================================================================
# src/agentic/qmd/tools/qmd.sh
# Maintenance CLI for the qmd (Quick Markdown) search engine — for humans and
# dev-bot lifecycle scripts, NOT exposed to agents.
#
# qmd is BM25-only in dev-bot (no models, no embeddings; ADR
# 20260913072905-qmd-bm25-only-no-model-downloads). Agent memory recall goes
# through the `search-memories` tool; direct qmd invocation is blocked by a
# guards rule. This wrapper is deliberately NOT a `.mcp.sh` script, so the
# devbot-tools MCP server does not expose it.
#
# Usage:
#   qmd.sh status                  # Show QMD health and collections
#   qmd.sh search "keywords"       # BM25 keyword search
#   qmd.sh get "#docid"            # Retrieve doc by ID
#   qmd.sh multi-get "glob"        # Retrieve multiple docs
#   qmd.sh update                  # Update the BM25 index
#   qmd.sh collection add ...      # Manage collections
#   qmd.sh context add ...         # Manage context entries
#   echo "keywords" | qmd.sh       # Pipe mode: stdin -> qmd
#   qmd.sh --help                  # Show usage
# =============================================================================

set -euo pipefail

# ── Help flag (check before qmd availability) ─────────────────────────────────

if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
  echo "Usage: qmd.sh [options] [command] [args...]"
  echo ""
  echo "Maintenance CLI for the qmd (Quick Markdown) search engine (BM25-only)."
  echo "Not exposed to agents — memory recall uses the search-memories tool."
  echo ""
  echo "Commands (forwarded to the qmd CLI):"
  echo "  status          Show QMD health and collections"
  echo "  search <kw>     BM25 keyword search"
  echo "  get <id>        Retrieve document by ID or path"
  echo "  multi-get <g>   Retrieve multiple documents by glob"
  echo "  update          Update the search index"
  echo "  collection      Manage collections (add, list, remove)"
  echo "  context         Manage context entries"
  echo ""
  echo "Pipe mode:"
  echo '  echo "keywords" | qmd.sh'
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

if ! command -v qmd >/dev/null 2>&1; then
  echo "FATAL: qmd CLI not found. Install with: npm install -g @tobilu/qmd" >&2
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
