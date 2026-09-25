---
date: 2026-09-24
keywords: ["devbot", "pull-request", "duplicate-work", "graphify", "rebase"]
trigger-on: ["check-open-pr-before-implementing"]
---

## Check for an open PR/branch covering the area before starting a fix

Before implementing a fix in a repo with other contributors, check whether someone already has it in flight — otherwise you can recreate an open PR commit-for-commit, touching the same files **and the same new test filenames**, which then conflicts on merge. The harness has the check built in: `graphify_list_prs` / `graphify_triage_prs` (every open PR with base and graph blast radius), plus `git branch -a --list '*<topic>*'` and `git log --oneline origin/<branch>`. Concretely: investigating a production log line produced three commits, two of which duplicated `origin/fix/driver-service-sync-silently-dropped` (PR #4700, open 18 days, same files, same test filenames) — the metadata guard and the after-commit/retry changes; only the third (the logging-severity fix, which that PR did not touch) was genuinely additive. The cost is not just wasted work: the duplicates had to be dropped in a rebase, and the rebase then conflicted on a file the merged PR had rewritten underneath, and a naive conflict resolution silently clobbered four tests the merge had added to that file. Run the check before the first edit, not after.
