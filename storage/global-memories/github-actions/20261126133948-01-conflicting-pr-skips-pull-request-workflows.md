---
date: 2026-11-26
keywords: ["github-actions", "pull_request", "checks", "conflicts", "mergeability"]
aliases: ["no checks reported", "pull_request workflow skipped"]
---

## A conflicting pull request runs no `pull_request` workflows

`gh pr checks` prints "no checks reported on the '<branch>' branch" and the Actions tab shows no run at all when the branch conflicts with its base. A `pull_request` workflow runs against the synthetic merge commit `refs/pull/<n>/merge`; when GitHub cannot compute it, the run is never created. Nothing fails, nothing warns — the check simply does not exist, which reads like "CI is broken" or "the workflow was removed".

Diagnose with `gh pr view <n> --json mergeable,mergeStateStatus` (`CONFLICTING` / `DIRTY`) and `gh api repos/<o>/<r>/actions/runs?head_sha=<sha>` returning `total_count: 0` for a head that was just pushed. Merge or rebase the base into the branch; the next push produces the run. Push and merge events, and `workflow_dispatch`, are unaffected.
