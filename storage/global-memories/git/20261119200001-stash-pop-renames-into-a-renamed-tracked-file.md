---
date: 2026-11-19
keywords: ["git", "stash", "rename-detection", "merge.renames", "modify-delete"]
aliases: ["stash pop clobbers a renamed file", "modify/delete conflict on pop"]
---

## A stash pop can merge your change into a renamed tracked file instead of conflicting

`git stash pop` after a release renamed a tracked path (`versions.env` → `versions.env.dist`, in the same commit that gitignored the old name) resolved the machine's modified `versions.env` **into** `versions.env.dist` when the two files were byte-identical — silently writing machine state into the release's own file, no conflict, no warning. With content that differed (a rewritten header) the same operation instead failed with `CONFLICT (modify/delete)` and left an unmerged path plus the stash entry. Same command, two outcomes, decided by rename similarity.

Make it deterministic: `git -c diff.renames=false -c merge.renames=false stash pop`. With rename detection off the rename is seen for what it is, so the machine's copy stays in the working tree as a delete-by-them/modified-by-them conflict, which you can then resolve by keeping the file (`git rm --cached --force <path>` when the new release gitignores it). Recognise the silent variant by a tracked file in the new base showing as modified right after a pop whose output mentions no conflict.
