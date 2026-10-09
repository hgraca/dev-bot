---
date: 2026-10-09
keywords: ["devbot", "grep", "search", "truncation", "false-negative"]
---

## A truncated search result is not evidence of absence

The agent `grep` tool caps its output (e.g. "Found 100 matches (more matches available)"). Reading a truncated list as complete and concluding "nothing matches X" produces a false negative that only surfaces later: in a dev-bot session a search over `*.bats` returned 100 matches with more available, and the tail held the one test asserting a module's skill count — the miss was caught only when the full suite failed on it. Treat any result carrying a truncation notice as partial — raise the limit, narrow with `file_pattern`/`path_filter`, or re-run the specific check directly — before reporting that something does not exist.
