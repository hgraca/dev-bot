#!/usr/bin/env bash
# ---
# description: Search with a digest instead of raw output — repo-safe exclusions, per-file counts, and the first few matches per file, so one call usually settles the question
# ---
# =============================================================================
# src/agentic/explore/tools/search.mcp.sh
# CLI wrapper for search.py.
#
# The corpus showed `rg -> rg` in 23% of sessions: the first result was
# unreadable, so the search was re-run with different flags. This prints a
# digest — file, count, top matches — and skips dependencies, build output and
# generated artefacts by default.
#
# Usage:
#   search.mcp.sh "def main"
#   search.mcp.sh "TODO" --path src --max-per-file 3
#   search.mcp.sh "class Foo" --glob '*.php' --ignore-case
#
# Exit: 0 matches found, 1 none, 2 usage, 3 ripgrep missing.
#
# Dependencies: python3, ripgrep
# =============================================================================

set -euo pipefail

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"search","description":"Search the repository with a digest instead of raw ripgrep output: repo-safe exclusions (dependencies, build output, generated artefacts, other worktrees) and a per-file summary — file, match count, first few matches — so one call replaces the re-runs caused by an unreadable first result. Exit 0 matches, 1 none.","parameters":{"type":"object","properties":{"pattern":{"type":"string","description":"Pattern to search for"},"path":{"type":"string","description":"Path to search (default: .)"},"glob":{"type":"array","items":{"type":"string"},"description":"Include globs, repeatable"},"exclude":{"type":"array","items":{"type":"string"},"description":"Extra directories to exclude"},"max_per_file":{"type":"integer","description":"Matches shown per file (default 5)"},"max_files":{"type":"integer","description":"Files listed (default 30)"},"fixed_strings":{"type":"boolean","description":"Treat the pattern literally"},"ignore_case":{"type":"boolean","description":"Case-insensitive search"}},"required":["pattern"]}}
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

exec python3 "${SCRIPT_DIR}/search.py" "$@"
