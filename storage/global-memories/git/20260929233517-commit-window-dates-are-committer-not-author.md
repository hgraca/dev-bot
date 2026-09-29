---
date: 2026-09-29
keywords: ["git", "committer-date", "author-date", "rebase", "time-to-fix"]
trigger-on: ["commit-date-window", "git-log-since-until", "defect-age-metric"]
---

## `git log --since/--until` filters on committer date, and author dates stop following topology after a rebase

`git log --since/--until` selects commits by **committer** date, but `%aI` (author date) is what most tooling reads back — so a window's selection basis and the dates a report prints can silently differ. Worse, a rebase rewrites committer dates while preserving author dates, so author dates no longer follow topological order: an interval computed as `inducing_author_date → fix_author_date` can come out **negative** for a genuine fix, and any defect-age metric built that way is unusable — a real case produced `−288.6 h` for a fix whose inducing commit was in fact an ancestor. Compute durations and orderings over commits from **committer** dates (or from topology, e.g. `git merge-base --is-ancestor`), and store both dates when a reader has to reconcile why a five-day window can contain a commit authored months earlier: a rebased commit is authored outside the window and committed inside it.
