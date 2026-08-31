---
date: 2026-06-16
keywords: ["devbot", "jsonc", "init.sh", "inline-python", "shell"]
---

## JSONC comment stripping must be inlined in Python shell scripts

When a shell script uses inline Python via `python3 -c "..."` to parse JSONC files (`.devbot.jsonc`, `.devbot.project.dist.jsonc`), using raw `json.load()` crashes on `//` and `/* */` comments. Inline scripts cannot import the project's canonical `src/_shared/read_jsonc.py` parser, so a compact `_strip_jsonc_comments(text)` helper must be inlined. The helper must be string-aware to preserve `//` (URLs) and `/* */` inside JSON string values. Pattern: replace `json.load(f)` with `json.loads(_strip_jsonc_comments(f.read()))`. Nine scripts were fixed for this bug in commit da21176, but `src/tools/devbot/init.sh` was missed — found when `.devbot.jsonc` root config grew a `//` comment on a `disabled_modules` field. When adding a new inline Python script that reads JSONC, start with the `_strip_jsonc_comments` helper from `src/_shared/read_jsonc.py` lines 14–56.
