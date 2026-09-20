---
date: 2026-09-16
keywords: ["git", "autosquash", "rebase", "fixup", "verification"]
trigger-on: ["git-autosquash-fixup", "git-fixup-commit"]
---

## An autosquash rebase can report a fixup as done without having applied it — verify by tree hash, not by status

During `git rebase -i --autosquash` a fixup may be "rescheduled", and git's own status output then lists it under **"Last commands done"** while the todo file still holds it — i.e. the status says applied, the state says pending. Continuing is correct (it applies then); removing the line as a duplicate would have **silently dropped that commit's changes**, and nothing in the rebase output would have said so. Two habits make this class of error detectable. (1) Before rewriting, record `git rev-parse HEAD^{tree}`; after, compare — squashing fixups reorganizes history without changing the final tree, so a **mismatch means content was lost or altered**. (2) To check whether a specific fixup landed, ask about its *content*, not its status: `git ls-tree -r --name-only HEAD | grep <a file it adds>` (or grep HEAD for a line it introduced). Recovery is cheap either way — the pre-rebase HEAD stays in `ORIG_HEAD`/reflog. Also note the flip side of the tree check: it is the *only* trustworthy signal here, because both `git status` and the rebase log were wrong in opposite directions.
