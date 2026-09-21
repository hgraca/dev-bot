---
date: 2026-09-21
keywords: ["git", "force-push", "rebase", "history-rewrite", "stale-branch"]
trigger-on: ["git-force-push", "git-rebase-history-rewrite"]
---

## Prove a force-push is safe by subject-matching the remote's old-SHA twins

A branch that was rewritten locally but never pushed leaves the remote holding the *pre-rewrite* commits, so `git log --oneline HEAD..origin/<branch>` lists commits with the same subjects as your rewritten ones but different SHAs. Matching each remote-only commit's subject against your rewritten commits proves they are superseded twins and that the remote carries no unique work — exactly the evidence needed before force-pushing. The raw count from `git rev-list --left-right --count HEAD...origin/<branch>` is misleading: after rebasing onto a moved default branch the "behind" number includes those twins and looks alarming until you list the subjects. Also create a named backup ref (`git branch backup/<topic>-pre-rebase HEAD`) before any rewrite, because `ORIG_HEAD` is overwritten by the next rebase and the reflog is the only other safety net.
