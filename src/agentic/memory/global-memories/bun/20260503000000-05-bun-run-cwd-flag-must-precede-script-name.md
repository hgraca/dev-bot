---
date: 2026-05-03
keywords: ["bun"]
---

## `bun run --cwd` flag must precede script name

`bun run build --cwd /path` silently ignores `--cwd` and runs in CWD, causing "Script not found" errors. Correct: `bun run --cwd /path build`. Fixed in commit b1c6dba.
