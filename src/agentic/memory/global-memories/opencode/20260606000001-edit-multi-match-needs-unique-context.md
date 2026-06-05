---
date: 2026-06-06
keywords: ["edit", "multi-match", "oldString", "opencode"]
---

## edit tool multi-match: oldString must be unique in file

When using the `edit` tool to modify a file, `oldString` must match exactly one location.
If it appears in multiple places, the tool fails with `Found multiple matches for oldString`.

**Fix**: Before editing, verify uniqueness with `grep` for the pattern. If multiple matches exist, include ≥3 surrounding lines (including headings, separators, or adjacent `---` lines) in the `oldString` to disambiguate. Prefer targeting a section heading or a unique combination of preceding and following lines.

**When it's safe to skip**: If the file is small (<20 lines) or the pattern is obviously unique (e.g. a function signature). If unsure, grep first.
