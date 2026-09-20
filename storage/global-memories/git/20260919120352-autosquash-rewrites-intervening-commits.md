---
date: 2026-09-19
keywords: ["git", "autosquash", "fixup", "rebase", "multi-agent"]
trigger-on: ["git-fixup-squash", "git-shared-branch-rebase"]
---

## Squashing a fixup rewrites every commit between it and its target

Folding a `fixup! X` into `X` with `git rebase -i --autosquash` replays the whole todo list, so every unrelated commit that landed between the fixup and its target is also replayed and gets a new SHA. On a shared branch where another agent is committing concurrently, that rewrites their history under them — confirm before running, and never squash while their work is in flight. The rewrite is content-safe if the final tree is unchanged: capture `git rev-parse HEAD^{tree}` before and after and require `git diff <pre> HEAD` to be empty — an identical tree proves nothing was lost even though every intervening SHA changed. Inspect the plan without executing it: `GIT_SEQUENCE_EDITOR='grep -v "^#" "$1"; false' git rebase -i --autosquash <base>` prints the arranged todo and aborts (there is no `--dry-run`); then apply with `GIT_SEQUENCE_EDITOR=:` once the plan is confirmed.
