---
date: 2026-04-12
keywords: ["opencode"]
---

## `opencode.dist.jsonc` contains `//` comments — never use `json.load`

Date: 2026-04-12 (updated 2026-05-06)
Any Python script that reads JSONC files (`opencode.dist.jsonc`, `.devbot.jsonc`, `.ai/devbot/devbot.jsonc`) must strip comments first. **Always use `from strip_jsonc import load_jsonc`** from `src/functions/strip_jsonc.py` — it handles `//`, `/* */`, string literals, trailing commas, and missing commas via a proper char-by-char scanner.

**Do NOT** copy-paste the inline `re.sub(r'(?m)(?<!:)//.*$', '', t)` regex — it only handles `//` and breaks on `/* */` blocks and trailing commas. Commit `da21176` (2026-05-06) eliminated 9 such duplicates after `make init` crashed parsing `.devbot.jsonc` containing a `//` comment inside an array. Pattern for shell heredocs: pass `${FUNCTIONS_PATH}` as first argv, then `sys.path.insert(0, sys.argv[1]); from strip_jsonc import load_jsonc`.
