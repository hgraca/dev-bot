---
layout: page
title: Git Report
description: Git state snapshot tool.
nav_section: docs
---

Captures a snapshot of the current git state: branch, recent commits, working tree status, staged diff, commits ahead of remote, and index integrity.

## What it reports

- Current branch and default remote branch
- Recent commit history
- Working-tree status (modified, staged, untracked)
- Staged diff (summary + full)
- Commits ahead of `origin/HEAD`
- Index integrity check (`git fsck`)

## How agents use it

Used by the `explore` module's `gather-context` skill to prime new sessions with the current git state.

## See also

- [Explore](/module-reference) — gather-context skill
