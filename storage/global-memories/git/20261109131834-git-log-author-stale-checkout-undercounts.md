---
date: 2026-11-09
keywords: ["git", "git log", "author", "stale checkout", "work history"]
---

## `git log --author` on a stale checkout under-counts a work history

A workspace of sibling repos usually has some checkouts parked on old feature branches — here `pricing-engine`, `exchange-rate`, `portal` and `flight-service` were months behind, one of them on a February branch. `git log --since=<window> --author=<me>` walks the checked-out branch, so it silently under-reports (0 of 15 commits in `pricing-engine`, 11 of 37 in `exchange-rate`), while `git log --all` over-counts by also reaching unmerged PR branches whose commits are later squash-merged. Census the **default branch ref** instead: `git log --since=… --author=<name> origin/$(git symbolic-ref --short refs/remotes/origin/HEAD | sed 's#origin/##')`. Expect some author dates to predate the window when work was rebased and merged inside it — report those under the merge window, not the author date.
