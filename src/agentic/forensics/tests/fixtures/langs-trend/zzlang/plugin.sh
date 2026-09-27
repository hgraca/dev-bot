#!/usr/bin/env bash
# Test fixture: a units-capable plugin whose complexity is the count of `if`
# lines in each `.zz` file — deterministic, no container needed.
set -euo pipefail

case "${1:-}" in
  meta) echo '{"lang":"zz","extensions":[".zz"],"capabilities":["units"]}' ;;
  units)
    python3 -c '
import json, os, sys
request = json.load(sys.stdin)
project = request["project"]
units = []
for relative in request.get("files", []):
    path = os.path.join(project, relative)
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        continue
    complexity = sum(1 for line in text.splitlines() if line.strip().startswith("if "))
    units.append({"path": relative, "name": os.path.basename(relative), "kind": "function",
                  "start_line": 1, "end_line": 1, "complexity": complexity,
                  "loc": len(text.splitlines()), "parent": ""})
print(json.dumps({"ok": True, "units": units, "errors": []}))
'
    ;;
  *) exit 1 ;;
esac
