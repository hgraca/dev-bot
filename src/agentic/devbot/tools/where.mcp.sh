#!/usr/bin/env bash
# ---
# description: Resolve the project context in one call — owning project, workflow, commit_memory, devbot_dir, datasources, where the memory lives and which files are active
# ---
# =============================================================================
# src/agentic/devbot/tools/where.mcp.sh
# CLI wrapper for where.py.
#
# A polyrepo session opens with project-for-path, then project-memory, sometimes
# project-for-path again for a second key. This answers all of it once.
#
# Usage:
#   where.mcp.sh                 # the current directory
#   where.mcp.sh /path/to/child  # resolve another path
#
# Exit: 0 resolved, 1 the resolver failed, 2 usage.
#
# Dependencies: python3, bash, the devbot-cli project-for-path tool
# =============================================================================

set -euo pipefail

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"where","description":"Resolve the project context in one call: owning project name and path, type and registration, the workflow in force, commit_memory, devbot_dir, datasources, the memory directory and the active memory files. Replaces the project-for-path plus project-memory plus second-key round trips a polyrepo session opens with.","parameters":{"type":"object","properties":{"path":{"type":"string","description":"Path to resolve (default: the current directory)"}}}}
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

exec python3 "${SCRIPT_DIR}/where.py" "$@"
