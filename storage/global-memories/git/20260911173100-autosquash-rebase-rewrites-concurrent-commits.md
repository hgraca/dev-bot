---
date: 2026-09-11
keywords: ["git", "autosquash", "rebase", "concurrent-agents"]
trigger-on: ["git-autosquash-rebase", "concurrent-agents-shared-branch"]
---

## An autosquash rebase replays commits that landed in its range, rewriting their SHAs

When several agents/sessions share a branch, `git rebase -i --autosquash <target>^` folds your own `fixup!` commits but also replays any commits another session committed onto the branch in the interval — their SHAs change, so that session's references go stale (content survives). Two hazards: (1) the rebase is blocked outright by foreign _unstaged_ changes ("cannot rebase: You have unstaged changes"), and `--autostash` only stashes _tracked_ changes, not untracked ones — if the foreign work is still uncommitted, `--autostash` briefly removes and reapplies it, risking a concurrent-agent race; (2) if the foreign work was committed just before the rebase, it is swept into the replay. Defensive habits: before autosquashing, run `git log --oneline <target>..HEAD` and confirm the range holds only your commits; prefer starting from a clean tree; when a concurrent session is active, defer the autosquash (leave the `fixup!` commits) rather than rebasing across their work; afterwards use `git reflog` to confirm exactly what was rewritten.
