---
date: 2026-05-03
keywords: ["opencode", "tool"]
---

## `git apply --3way` doesn't create unmerged index entries — can't use `git checkout --theirs`

When `git apply --3way` encounters conflicts, it writes conflict markers to the working tree but stages the file normally (no unmerged state). `git diff --diff-filter=U` returns nothing, and `git checkout --theirs` does nothing. This makes automated conflict resolution impossible via standard git tools. Fix: use `git apply --check` first; if it fails, skip the patch entirely rather than attempting resolution.
