---
date: 2026-11-17
keywords: ["git", "autosquash", "rebase", "squash", "reset-soft"]
aliases: ["GIT_SEQUENCE_EDITOR=cat", "dry run rebase plan", "reset --soft origin/main"]
---

## `GIT_SEQUENCE_EDITOR=cat` is not a dry run, and never squash against a moved `origin/main`

Two traps when collapsing a branch's own commits before pushing. First, `GIT_SEQUENCE_EDITOR=cat git
rebase -i --autosquash origin/main` does not merely print the plan: `cat` exits 0 without editing, so
git **runs** it — the rebase starts, and if output is truncated or the editor misbehaves it parks
mid-plan ("you are currently editing a commit") with the fixups still pending. `git rebase --continue`
then replays a fixup onto a commit that already contains it and conflicts. Show the plan without
starting a rebase (derive it from `git log --oneline origin/main..HEAD` and each fixup's `--stat`), and
apply it with `GIT_SEQUENCE_EDITOR=:`.

Second, `git reset --soft origin/main` is only a squash when `origin/main` is still the branch's own
base. Another session can push to `origin/main` while you work; the reset then moves HEAD to a
**descendant** of the branch's base, so the commit records reversions of those newer commits. Reset
against the branch's base instead — `git reset --soft "$(git rev-parse <first-branch-commit>^)"` —
and verify with `git diff --cached --stat` (only your files) and `git diff <old-tip> HEAD -- <your
paths>` (empty). A non-empty diff against the whole tree is expected once the base moved; it is not a
sign the squash lost work.
