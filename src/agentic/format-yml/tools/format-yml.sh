#!/usr/bin/env bash
# ---
# description: Format YAML files with consistent 2-space indentation via prettier
# ---
# src/agentic/format-yml/tools/format-yml.sh
# CLI wrapper — formats YAML files with 2-space indentation via format-yml.py.
set -euo pipefail

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"format-yml","description":"Format YAML files with consistent 2-space indentation via prettier","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"File path(s) to format"}},"required":["args"]}}
JSON
    exit 0
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
exec python3 "${SCRIPT_DIR}/format-yml.py" "$@"
