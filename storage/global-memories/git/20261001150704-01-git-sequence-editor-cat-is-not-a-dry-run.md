---
date: 2026-10-01
keywords: ["git", "rebase", "autosquash", "dry-run"]
trigger-on: ["git-autosquash-dry-run"]
---

## GIT_SEQUENCE_EDITOR=cat is not a rebase dry run

Running `GIT_SEQUENCE_EDITOR=cat git rebase -i --autosquash <base> | head` to peek at the plan starts a real interactive rebase — `cat` exits 0, so git proceeds — and when `head` closes the pipe git takes SIGPIPE mid-run, leaving a `.git/rebase-merge` directory and a detached HEAD. Use the documented preview instead: `GIT_SEQUENCE_EDITOR='grep -v "^#" "$1"; false' git rebase -i --autosquash <base>` prints the todo and fails, so git aborts untouched. If it already happened, `git rebase --abort` restores ORIG_HEAD; confirm with `git log --oneline` and `git rev-parse HEAD^{tree}`.
