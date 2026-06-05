#!/usr/bin/env bash
# ---
# description: List sibling projects configured in the global devbot config, each with its name, full path, and whether the agent has access to it.
# ---
# =============================================================================
# src/tools/devbot/tools/list-projects.sh
# Lists the sibling projects configured in .devbot.global.jsonc's `projects`
# array. Each entry reports the project name (its last folder name), the full
# path, and whether the agent has access to it (directory exists and is readable).
#
# Usage:
#   list-projects.sh             # markdown table
#   list-projects.sh --json      # JSON array
#
# Dependencies: python3, src/_shared/read_jsonc.py
# =============================================================================

set -euo pipefail

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"list-projects","description":"List sibling projects configured in the global devbot config (.devbot.global.jsonc), each with its project name (last folder name), full path, and whether the agent has access to it.","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"CLI args: [--json]"}},"required":["args"]}}
JSON
    exit 0
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
DEV_BOT_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
CONFIG_FILE="${DEV_BOT_ROOT}/.devbot.global.jsonc"
READ_JSONC="${SCRIPT_DIR}/../../../_shared/read_jsonc.py"

OUTPUT_FORMAT="markdown"
[[ "${1:-}" == "--json" ]] && OUTPUT_FORMAT="json"

if [[ -f "${CONFIG_FILE}" ]]; then
  python3 "${READ_JSONC}" "${CONFIG_FILE}" projects
else
  echo "[]"
fi | python3 -c '
import json
import os
import sys

fmt = sys.argv[1]

try:
    projects = json.load(sys.stdin)
except (json.JSONDecodeError, ValueError):
    projects = []

if not isinstance(projects, list):
    projects = []

rows = []
for path in projects:
    if not isinstance(path, str) or not path:
        continue
    name = os.path.basename(path.rstrip("/"))
    access = os.path.isdir(path) and os.access(path, os.R_OK)
    rows.append({"name": name, "path": path, "access": access})

if fmt == "json":
    print(json.dumps(rows, indent=2))
else:
    print("## Sibling Projects")
    print()
    if not rows:
        print("_No projects configured._")
    else:
        print("| Name | Path | Access |")
        print("| --- | --- | --- |")
        for r in rows:
            print("| {} | {} | {} |".format(r["name"], r["path"], "yes" if r["access"] else "no"))
' "${OUTPUT_FORMAT}"
