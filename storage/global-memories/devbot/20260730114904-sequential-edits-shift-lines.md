---
date: 2026-07-30
keywords: ['devbot', 'edit', 'sequential-edits', 'line-shift', 'oldstring-matching']
trigger-on: ['sequential-file-edits', 'multiple-edits-same-file']
---

## Sequential edits on same file shift line numbers — verify between each edit

When making multiple `edit` tool calls on the same file in sequence, each edit changes the file content and shifts line numbers. The next edit's `oldString` must match the file in its current state, not the state from the initial `read`. If the first edit appears to succeed but verification uses stale line-number-based reads, the output may show different content than expected (e.g., the removed block still present at a different offset). Always re-read the exact target section after each edit before verifying or making the next edit.
