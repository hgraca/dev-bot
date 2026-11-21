#!/usr/bin/env bash
# ---
# description: Run a command inside the project's compose container without naming it — resolves the container by service (or the only running one) and execs there
# ---
# =============================================================================
# src/agentic/docker/tools/docker-exec.mcp.sh
# CLI wrapper for docker-exec.
#
# The corpus showed `docker exec transfers-app-1 <command>` chains: the container
# name is discovered once and retyped for every follow-up command.
#
# Usage:
#   docker-exec.mcp.sh php artisan migrate
#   docker-exec.mcp.sh --service app composer install
#   docker-exec.mcp.sh --list
#   docker-exec.mcp.sh --path /srv/project -- php -v
#
# Exit: 0 success, the command's own code otherwise, 2 usage, 3 no/ambiguous
# target.
#
# Dependencies: python3, docker (compose v2)
# =============================================================================

set -euo pipefail

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"docker-exec","description":"Run a command inside the project's compose container without naming it: resolves the container from the compose project (by --service, or the only running one) and execs there. Replaces retyped `docker exec <generated-name> ...` chains. Use --list to see the candidates when several match.","parameters":{"type":"object","properties":{"command":{"type":"array","items":{"type":"string"},"description":"Command and arguments to run inside the container"},"service":{"type":"string","description":"Compose service name (default: the only running container)"},"path":{"type":"string","description":"Project directory (default: the current directory)"},"list":{"type":"boolean","description":"List the project's containers and exit"}},"required":["command"]}}
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

exec python3 "${SCRIPT_DIR}/docker-exec.py" "$@"
