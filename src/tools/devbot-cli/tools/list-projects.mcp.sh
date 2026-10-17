#!/usr/bin/env bash
# ---
# description: List sibling projects configured in the global devbot config, each with its name, full path, and whether the agent has access to it.
# ---
# =============================================================================
# src/tools/devbot-cli/tools/list-projects.mcp.sh
# Lists the sibling projects configured in .devbot.global.jsonc's `projects`
# array. Each entry reports the project name (its last folder name), the full
# path, and whether the agent has access to it (directory exists and is readable).
#
# Usage:
#   list-projects.mcp.sh             # markdown table
#   list-projects.mcp.sh --json      # JSON array
#
# Dependencies: python3, src/_shared/read_jsonc.py
# =============================================================================

set -euo pipefail

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"list-projects","description":"List sibling projects configured in the global devbot config (.devbot.global.jsonc), each with its project name (last folder name), full path, and whether the agent has access to it. Filter with --filter <regex> or --only <names>; --compact drops the table header.","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"CLI args: [--json] [--filter <regex>] [--only <name[,name]>] [--compact]"}},"required":["args"]}}
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
DEV_BOT_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
CONFIG_FILE="${DEV_BOT_GLOBAL_CONFIG:-${DEV_BOT_ROOT}/.devbot.global.jsonc}"
READ_JSONC="${SCRIPT_DIR}/../../../_shared/read_jsonc.py"

OUTPUT_FORMAT="markdown"
FILTER=""
ONLY=""
COMPACT=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) OUTPUT_FORMAT="json"; shift ;;
    --filter)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: --filter requires a regex" >&2
        exit 2
      fi
      FILTER="$2"; shift 2
      ;;
    --filter=*) FILTER="${1#--filter=}"; shift ;;
    --only)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: --only requires a comma-separated list" >&2
        exit 2
      fi
      ONLY="$2"; shift 2
      ;;
    --only=*) ONLY="${1#--only=}"; shift ;;
    --compact) COMPACT=true; shift ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 2
      ;;

  esac
done

if [[ -f "${CONFIG_FILE}" ]]; then
  python3 "${READ_JSONC}" "${CONFIG_FILE}" projects
else
  echo "[]"
fi | python3 -c '
import json
import os
import re
import sys

fmt, filter_pattern, only_names, compact = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "true"

try:
    projects = json.load(sys.stdin)
except (json.JSONDecodeError, ValueError):
    projects = []

if not isinstance(projects, list):
    projects = []

only = {name.strip() for name in only_names.split(",") if name.strip()}
try:
    pattern = re.compile(filter_pattern) if filter_pattern else None
except re.error as exc:
    print(f"ERROR: invalid --filter regex: {exc}", file=sys.stderr)
    sys.exit(2)
rows = []
for path in projects:
    if not isinstance(path, str) or not path:
        continue
    name = os.path.basename(path.rstrip("/"))
    if only and name not in only:
        continue
    if pattern and not (pattern.search(name) or pattern.search(path)):
        continue
    access = os.path.isdir(path) and os.access(path, os.R_OK)
    rows.append({"name": name, "path": path, "access": access})

if fmt == "json":
    print(json.dumps(rows, indent=2))
elif compact:
    for r in rows:
        print("{}\t{}\t{}".format(r["name"], r["path"], "yes" if r["access"] else "no"))
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
' "${OUTPUT_FORMAT}" "${FILTER}" "${ONLY}" "${COMPACT}"
