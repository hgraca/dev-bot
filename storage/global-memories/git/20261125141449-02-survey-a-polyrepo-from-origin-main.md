---
date: 2026-11-25
keywords: ["git", "polyrepo", "origin-main", "stale-checkout"]
aliases: ["stale checkout", "cross-repo sweep", "read from origin/main"]
---

## Survey a polyrepo from `origin/main`, not the main checkouts

A polyrepo's child checkouts drift: several were dozens of commits behind, so reading their working-tree files produced a plan built on stale content — a compose `name:` that had since become `${PROJECT_NAME:-...}`, and a "warranted" change list that included a repo which had already fixed the issue in a file my scan never looked at. Read the file you are about to change with `git -C <repo> show origin/main:<path>`, and base any cross-repo sweep on that rather than on the checkout. Worktrees are cut from `origin/main`, so a plan validated against the checkout can disagree with the branch the change lands on — the first review round then catches it, at the cost of a fixup and a re-review.
