---
date: 2026-11-03
keywords: ["git", "remote", "push", "pull-request"]
aliases: ["wrong remote", "fork instead of origin", "remote -v head"]
---

## `git remote -v | head -1` is the alphabetically first remote, not the canonical one

A repo that carries both a personal fork and the org repo lists them alphabetically, so `git remote -v | head -1` can hand back the fork. Pushing there and opening a PR against it produced a PR on `hgraca/dev-bot` instead of `GET-E/dev-bot`; the repair was to close that PR, delete the fork branch, push to `origin`, and open the PR again. Resolve the target from the branch's upstream instead — `git rev-parse --abbrev-ref <default>@{upstream}` (e.g. `origin/main`) and take the remote from that — and refuse to open a PR when the repo has more than one remote and none of them is the tracked one.
