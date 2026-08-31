---
date: 2026-06-06
keywords: ["edit", "back-to-back", "reread", "opencode"]
---

## Back-to-back edits on same file: after first edit, re-read before second

When making two `edit` calls on the same file in sequence, the first edit changes line numbers and context.
The second edit's `oldString` may no longer match at the intended location because the first edit shifted content.

**Fix**: After the first edit completes and the tool confirms success, re-read the file with `read` to get fresh line numbers before crafting the second `oldString`. Alternatively, batch both edits into a single `edit` call that replaces the full section between two stable boundaries.

**When it's safe to skip**: When edits are in non-overlapping sections (e.g. the header and the footer) — `oldString` uniqueness is determined independently per call, not by the cumulative file state.
