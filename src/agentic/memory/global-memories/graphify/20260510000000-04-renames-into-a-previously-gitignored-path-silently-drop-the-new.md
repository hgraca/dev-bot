---
date: 2026-05-10
keywords: ["graphify", "graph"]
---

## Renames into a previously-gitignored path silently drop the new file

During the [[2026-05-10T17-37-src-reorg-plan]] reorg, `git mv src/commands/patch-opencode/ src/instructions/commands/patch-opencode/` was committed (db7a29a) as a delete + add. But because `.gitignore` still had `src/commands/patch-opencode/` patterns that ALSO matched the new path (the `*opencode*` wildcard at line 39 catches both), the "add" half of the rename was silently ignored. Result: files showed as `deleted` in the rename commit and `untracked` afterward — easy to miss until a later `git status` check.
Fix: When moving files into a path covered by an existing gitignore wildcard, update `.gitignore` (and `.graphifyignore`) to un-ignore the new path BEFORE the `git mv`. If discovered after the fact, run `git add -A` once the gitignore is fixed; git will pick up the new path as a fresh add (recovered in commit `d925008`).
