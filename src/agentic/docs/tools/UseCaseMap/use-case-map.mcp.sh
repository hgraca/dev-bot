#!/usr/bin/env bash
# ---
# description: Generate a UseCaseMap architecture diagram JSON from a PHP codebase. Traces call chains from entry points through commands, handlers, ports, adapters, and HTTP clients. Requires a PHP project (composer.json) and a local PHP CLI or Docker for full command/handler/event resolution; without them only declaration-based discovery runs.
# ---
# =============================================================================
# src/agentic/docs/tools/UseCaseMap/use-case-map.mcp.sh
# Generates a UseCaseMap architecture diagram from a PHP codebase.
# Delegates to create-use-case-map.py.
#
# Usage:
#   use-case-map.mcp.sh [--project-root <dir>] [--output <file>] [--component <name>]
#                   [--title <title>] [--subtitle <subtitle>] [--copy-visualizer <path>]
#
# Parameters:
# - project-root (string, optional): PHP project root directory (default: current working directory)
# - output (string, optional): output file path (default: stdout)
# - component (string, optional): filter to a specific component (e.g. Billing)
# - title (string, optional): diagram title
# - subtitle (string, optional): diagram subtitle
# - copy-visualizer (string, optional): copy the UseCaseMap HTML visualizer to the specified path
# =============================================================================

set -euo pipefail

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"use-case-map","description":"Generate a UseCaseMap architecture diagram JSON from a PHP codebase. Traces call chains from entry points through commands, handlers, ports, adapters, and HTTP clients. Requires a PHP project (composer.json) and a local PHP CLI or Docker for full command/handler/event resolution; without them only declaration-based discovery runs.","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"CLI args: [--project-root <dir>] [--output <file>] [--component <name>] [--title <title>] [--subtitle <subtitle>] [--copy-visualizer <path>]"}},"required":["args"]}}
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
PY_SCRIPT="${SCRIPT_DIR}/create-use-case-map.py"

if [[ ! -f "$PY_SCRIPT" ]]; then
  echo "use-case-map: script not found at ${PY_SCRIPT}" >&2
  exit 1
fi

exec python3 "$PY_SCRIPT" "$@"
