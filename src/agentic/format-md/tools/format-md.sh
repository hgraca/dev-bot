#!/usr/bin/env bash
# ---
# description: Format markdown files with consistent formatting via prettier
# ---
# src/agentic/format-md/tools/format-md.sh
# CLI wrapper — formats markdown files via prettier (format-md.py).
set -euo pipefail

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"format-md","description":"Format markdown files with consistent formatting via prettier","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"File path(s) to format"}},"required":["args"]}}
JSON
    exit 0
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
exec python3 "${SCRIPT_DIR}/format-md.py" "$@"
