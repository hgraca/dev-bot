---
date: 2026-09-29
keywords: ["git", "github-actions", "merge", "ci", "semantic-conflict"]
trigger-on: ["pr-merge-commit-ci", "semantic-merge-conflict"]
---

## A pull_request CI run builds the PR merge commit, so two green branches can merge red

A GitHub Actions workflow triggered by `pull_request` checks out `refs/pull/<n>/merge` — the test merge of head into base — not the PR head SHA, so static analysis or tests can fail on a state that exists in neither branch's own tree. This is a "semantic merge conflict": one branch renames or deletes a symbol while another branch's later commit adds a reference to it; each branch is green alone, the merged tree has a dangling reference (`class.notFound`), yet the merge is textually clean and the diff shows no conflict. Diagnose without touching the worktree: `git fetch origin 'refs/pull/<n>/merge:refs/remotes/origin/pr-<n>-merge'`, then `git merge-tree --write-tree <head> origin/<base>` (a bare tree SHA with no conflict output = textually clean) and inspect the merged content with `git show <sha>:<path>` / `git ls-tree -r <sha>`. Fix by rebasing the PR branch onto the advanced base and migrating the dependency inside the commit that introduced the incompatibility. Beware two traps: the run's `headSha` is the PR head rather than what CI checked out, so comparing it to local HEAD is misleading; and searching local refs for the flagged path returns nothing until the merge ref is fetched.
