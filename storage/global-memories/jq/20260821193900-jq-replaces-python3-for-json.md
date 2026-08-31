---
date: 2026-08-21
keywords: ["jq", "json", "shell", "python3"]
---

## jq replaces python3 for JSON in shell scripts — idiom mapping + boolean gotcha

dev-bot's shell scripts use `jq` (a declared dependency) for JSON instead of `python3 -c 'import json…'` (macOS ships no python3). Common mappings: membership check `python3 … "sys.exit(0 if 'X' in list else 1)"` → `jq -e 'index("X") != null'` (the `-e` flag turns truthy/falsy into exit 0/1); print array elements `for m in list: print(m)` → `jq -r '.[]'`; field extraction `.get('field', default)` → `jq -r '.field // default'`.

**Boolean capitalization gotcha**: `jq -r '.blocked'` emits lowercase `true`/`false`, but `python3 print(True)` emits `True`/`False`. If downstream compares `[[ "$v" == "True" ]]`, use `jq -r 'if (.blocked // false) then "True" else "False" end'` to preserve the capitalised form.

**Boundary**: jq cannot parse JSONC (`//` comments) — those sites must keep `read_jsonc.py`/python. Read-modify-write of JSON files (`json.load → mutate → json.dump(indent=2)`) also stays python: jq loses the `indent=2` formatting and the rewrite is riskier churn.
