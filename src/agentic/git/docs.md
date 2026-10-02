---
title: "Git"
description: "Git workflow skills and tools — commit craft, history surgery, release notes, and a git-state report."
commands: ["commit", "release"]
skills: ["git-advanced-operations", "git-atomic-commits", "git-changelog", "git-commits", "git-conventional-commits", "git-fixup-commits", "git-report", "git-worktrees"]
tools: ["git-report", "release", "worktree"]
---

Everything an agent needs to make safe, reviewable commits — and to inspect or repair history when it goes wrong.

## What it does

- **Commit craft**: `git-commits` (subject form and the Problems/Solutions body), `git-conventional-commits` (the type/scope taxonomy), `git-atomic-commits` (one logical change per commit, staged file by file), and `git-fixup-commits` (correcting an earlier commit on the branch).
- **History surgery**: `git-advanced-operations` — partial staging, splitting a commit already made, and reflog recovery.
- **Worktrees**: `git-worktrees` and the `worktree` tool isolate each task's commits under `<devbot_dir>/worktrees/`, cut from the remote default branch, leaving the main checkout untouched.
- **Releases**: `git-changelog` writes the release file from the branch's commits; the `release` command and tool are the entry point.
- **Inspection**: the `git-report` tool snapshots the repository state before you commit, review, or plan.

## What git-report reports

- Current branch and default remote branch
- Recent commit history
- Working-tree status (modified, staged, untracked)
- Staged diff (summary + full)
- Commits ahead of `origin/HEAD`
- Index integrity check (`git fsck`)

## How agents use it

The `git-report` tool primes new sessions with the current git state (the `explore` module's `gather-context` skill calls it), and the commit skills run at the end of every task, before the commit is written.

## Configuration

`worktrees` (boolean, default `true`) — when `false`, agents edit and commit in the main checkout instead of isolating each task in a worktree. Project config overrides global. See [Configuration](/configuration#worktrees).

## See also

- [Explore](/modules/agentic/explore) — gather-context skill
- [Configuration](/configuration) — commit and branch settings
