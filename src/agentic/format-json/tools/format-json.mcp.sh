#!/usr/bin/env bash
# ---
# description: Format JSON and JSONC files with consistent 2-space indentation via prettier
# ---
# src/agentic/format-json/tools/format-json.mcp.sh
# CLI wrapper — formats JSON and JSONC files with consistent indentation via format-json.py.
set -euo pipefail

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"format-json","description":"Format JSON and JSONC files with consistent 2-space indentation via prettier","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"File path(s) to format"}},"required":["args"]}}
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
exec python3 "${SCRIPT_DIR}/format-json.py" "$@"
