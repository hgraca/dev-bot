---
date: 2026-11-27
keywords: ["github-actions", "gh-run-list", "commit-filter", "short-sha"]
aliases: ["gh run list --commit returns nothing", "short SHA does not filter runs"]
---

## `gh run list --commit` matches only a full SHA

`gh run list --commit <sha>` filters server-side on the run's `head_sha`, and a short SHA matches
nothing — the command exits 0 with an empty list, which reads as "no runs for this workflow". Resolve
the prefix first (`gh api repos/<owner>/<repo>/commits/<prefix> --jq .sha` also accepts a branch or tag
name) and pass the full SHA; keep a client-side `startswith` check as the second line. Only the list
filter needs it — `gh run view <id> --json ...` takes the number and works on its own.
