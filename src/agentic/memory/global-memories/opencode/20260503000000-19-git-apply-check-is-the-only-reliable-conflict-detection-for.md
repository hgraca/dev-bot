---
date: 2026-05-03
keywords: ["opencode", "tool"]
---

## `git apply --check` is the only reliable conflict detection for PR patches

PR patches targeting `dev` branch have structural differences from version tags. `git apply --3way` does NOT create unmerged index entries — it writes conflict markers to the working tree and stages normally. `git diff --diff-filter=U` returns nothing. `git checkout --theirs` does nothing. Fix: use `git apply --check` first; if it fails, skip the patch entirely with `git reset --hard`.
