---
date: 2026-05-17
keywords: ["qmd", "search", "truncation", "json", "stdout"]
---

## `qmd search --all` silently truncates stdout at 65536 bytes (64 KB)

When `qmd search --all` returns enough results to exceed 64 KB of JSON output, the CLI silently truncates stdout mid-string, producing invalid JSON that fails `json.loads()` with `JSONDecodeError: Unterminated string`. The truncation is exact at 65536 bytes. The fix is to replace `--all` with `-n <max_results>` so the result count is always bounded by the caller's limit. In `search-memories.py` the affected line was `cmd = ["search", query, "--json", "--all"]` — changed to `cmd = ["search", query, "--json", "-n", str(max_results)]`. See [[global/qmd/20260415000000-01-qmd-index-path-is-controlled-via-xdgcachehome-only.md]].
