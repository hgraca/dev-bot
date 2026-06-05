---
date: 2026-05-03
keywords: ["opencode", "plugin", "tool"]
---

## OpenCode returns `"(no output)"` string — not empty string — for empty command results

When a Bash tool call produces no stdout, OpenCode passes the literal string `"(no output)"` (not `""`) to the after hook's `output.result.stdout`. Any plugin logic checking for empty results must match both `""` and `"(no output)"`.
