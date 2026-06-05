---
date: 2026-05-03
keywords: ["opencode", "tool"]
---

## Cross-branch patches: don't try to resolve conflicts, just skip

When applying a GitHub PR patch (targeting `dev`) onto a version tag, `git apply` fails if context lines differ. Attempted fixes that ALL failed: (1) `git apply --3way` — leaves conflict markers but no unmerged index entries, so `git checkout --theirs` and `git diff --diff-filter=U` don't work; (2) regex marker stripping — "theirs" block is from dev context, doesn't fit tag-version surrounding code → syntax errors; (3) `git checkout FETCH_HEAD -- <file>` — takes whole file from dev branch which has different imports/modules → build errors. **Final fix**: use `git apply --check` first. If clean → apply. If conflicts → skip that patch, `git reset --hard`, continue with others. Only patches that apply cleanly to the current version tag should be used.
