---
date: 2026-10-16
keywords: ["git", "commit", "fixup", "autosquash"]
aliases: ["--fixup", "--squash", "rebase --autosquash", "GIT_EDITOR"]
trigger-on: ["git-fixup-commit"]
---

## `--fixup` keeps the prefix and is squash-safe; `--squash` opens a message editor

`git commit --fixup=<sha>` writes `fixup! <target subject>` and appends any `-m` as the body, so
`GIT_SEQUENCE_EDITOR=true git rebase -i --autosquash <base>` folds it in non-interactively — the
fixup body is discarded and the target's message wins. `git commit --squash=<sha>` instead writes
`squash! <subject>` and, on autosquash, **combines messages and opens the commit editor**: with no
`GIT_EDITOR` set the rebase hangs (past the bash tool's 120 s timeout) and the combined message
becomes the `# This is a combination of N commits` boilerplate. To attach a note to the target's
message, rebuild the commit cleanly (`git reset --soft <base>` then one commit) rather than using
`--squash`. Squashing an already-pushed branch needs a force-push — squash before the first push.
