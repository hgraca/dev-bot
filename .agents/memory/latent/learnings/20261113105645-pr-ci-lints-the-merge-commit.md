---
date: 2026-11-13
keywords: ["devbot", "ci", "lint", "pull-request", "prettier"]
aliases: ["main is red for every PR", "lint passes on push fails on PR", "inherited lint failure"]
---

# A pull request lints the merge commit, so main's `.agents/` lint debt blocks every PR

## The trap

`.github/workflows/` runs `make lint` on `pull_request`, and GitHub builds `refs/pull/N/merge` — the PR head **merged with the base branch**. The same workflow on `push` to `main` skips `.agents/**`. So an unformatted memory note committed straight to `main` is invisible to main's own CI and fails the lint job of _every_ open pull request, with the offending path being a file the PR author never touched.

Diagnosis is confusing because `gh pr checks` shows a red `lint` while every local `make lint` passes — the local checkout does not have the base branch's new file. `git ls-tree -r --name-only origin/main | grep <path>` confirms it came from the base.

## What to do

- Confirm it is inherited before touching it: check whether the file exists on `origin/main` and whether `prettier --check` fails on **that** version.
- Fix it on the PR branch after merging `origin/main` into it, as its own commit (`style(memory): …`). Adding the file without the merge creates an add/add conflict.
- Expect the rebase to _skip_ your commit if someone else already fixed it on `main` (`skipped previously applied commit`) — that is the correct outcome, not a lost commit.

The durable fix is in the workflow, not the branch: lint the same paths on `push` as on `pull_request`, or exclude `.agents/**` from both.
