---
date: 2026-11-26
keywords: ["devbot", "pr-watch", "gh-review-loop", "ci-gate", "pull-request"]
aliases: ["pr-watch returns before checks", "review loop waits on the wrong signal"]
---

## pr-watch exits on the review decision, not on the checks

`devbot tool pr-watch <pr> --no-request` answers exit 0 as soon as the decision is final — a landed Copilot review, even with `checks: pending (N checks)` and 0 polls — so a loop that treats that 0 as "gate green" hands over a pull request whose required checks are still running. Its exit 3 only reports a required check that had already failed when it polled. Drive the two legs separately: read the review from the exit 0, then wait on CI with `gh run watch <run-id> --exit-status --interval 30` (find the id with `gh run list --branch <branch> --json databaseId,status,workflowName`) and only then read `gh pr checks <pr> --required --json name,bucket` and `gh pr view <pr> --json mergeable,mergeStateStatus`.
