---
date: 2026-08-21
keywords: ["jq", "json", "python3", "boundary"]
---

## python3 → jq conversion boundary: what jq genuinely can't do

When deciding whether to convert a `python3 -c` JSON site to jq, the hard boundary is:

- **jq has no filesystem, time, socket, or collections modules.** Sites using `os.path.isdir`, `shutil`, `time.strptime`/`mktime`/`strftime` (timestamp TTL checks), `socket`, `re`, or `Counter` cannot be converted — those genuinely need Python.
- **Read-modify-write with timestamps stays Python.** The common blocker isn't formatting (jq's default indent=2 actually matches `json.dump(indent=2)`); it's that lock/counter/trigger files embed `int(time.time())` / `strftime` timestamps and do `strptime` TTL math, which jq cannot express.
- **JSONC needs `read_jsonc.py`.** jq cannot parse `//`/`/* */` comments; consolidate naive inline `strip '//'` snippets to `read_jsonc.py <file> | jq -r '.field // default'`.

Only pure JSON parse/extract (membership, field access, array iteration) converts cleanly to jq.
