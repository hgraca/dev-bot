---
date: 2026-09-27
keywords: ["opencode", "external_directory", "jsonc", "reconcile"]
---

# Producer formatting that glues braces defeats a line-shape block finder

`src/harnesses/opencode/init.sh::_reconcile_external_directory` rebuilt the
`permission.external_directory` block by splicing entries into the matched
`{...}` group, but the join had no leading/trailing newline — the output read
`"external_directory": {    "*": "deny",` … `"allow"},`, braces glued.

`src/_shared/upsert_opencode_permission.py` then found the block's close by
scanning for a line whose `.strip()` was exactly `}`/`}`, — which never matched
the glued close, so it walked into the _next_ block (`"bash"`), saw the install
path already present there, printed "already present", and no-op'd. The agent
silently lost read access to the dev-bot install, and `2>/dev/null || true` at
the fixture call sites hid it (audit-65 FAIL-1).

Rule: never locate a JSONC block by line shape. Count braces while skipping
strings **and comments** (`//`, `/* */`) — a `}` in a comment ends a naive scan
early. And when a self-heal step swallows its own stderr/status, a failure looks
exactly like a no-op. The reconciler now lives in
`src/_shared/reconcile_external_directory.py` and emits the block from the key's
own indentation; the upsert scans brace-depth, comment-aware.
