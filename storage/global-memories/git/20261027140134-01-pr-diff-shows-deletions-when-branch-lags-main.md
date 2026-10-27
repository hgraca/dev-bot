---
date: 2026-10-27
keywords: ["git", "pull-request", "merge-base", "rebase", "code-review"]
aliases: ["phantom deletions in PR", "branch behind main", "stale base review noise", "PR appears to delete files"]
trigger-on: ["pull-request-review", "force-push"]
---

## A branch that lags the default branch reviews as if it deleted newer upstream files

When a branch is cut before a commit lands on the default branch, a force-push keeps the old base, and the pull request's diff can then read as though it removed the newer upstream files — Copilot and human reviewers report deletions that the branch never made. Rebase onto the current default branch (and re-verify the tree hash against the intended diff) before requesting another review; do not "fix" the phantom deletion. Symptom to recognise: review comments about files the author never opened, arriving right after a force-push.
