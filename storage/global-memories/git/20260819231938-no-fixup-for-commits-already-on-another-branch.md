---
date: 2026-08-19
keywords: ["git", "fixup", "rebase", "shared-history", "atomic-commits"]
trigger-on: ["fixup-target-on-main", "shared-branch-rewrite"]
---

## No fixup commits for targets already on another branch

Before creating `git commit --fixup=<sha>` commits, verify the target is actually unique to the current branch: `git branch --contains <sha>` and `git branch -r --contains <sha>` (empty remote list means not pushed). If the target already exists on `origin/main` (shared, pushed history), fixups are the wrong tool — autosquashing them rewrites a branch other agents/humans track and demands a force-push approval. Use new atomic commits instead: check `git log --oneline main..HEAD` to confirm nothing is safe to fold, then group the working-tree changes into conventional commits. A rename in the change set can force coupling (e.g. renaming a file a test references breaks the old test path), so bundle the rename with the required test-path updates in one commit to keep each commit green.
