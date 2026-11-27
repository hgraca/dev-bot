---
date: 2026-11-26
keywords: ["git", "worktree", "origin-main", "rebase-autosquash"]
aliases: ["tree hash changed after squash", "base moved during a session"]
trigger-on: ["git-worktree-squash", "git-autosquash-rebase"]
---

## `origin/main` can move under a linked worktree mid-session

Worktrees share `refs/remotes` with every other checkout of the repository. A fetch in the main checkout — or another agent working in the same repository — fast-forwards `origin/main` beneath a session that never fetched anything, and a later `git rebase -i --autosquash origin/main` replays the branch onto that newer base. The signature is a squash whose tree hash differs from the pre-squash `HEAD^{tree}`: that is not a bad squash, it is a moved base. Confirm with `git reflog show origin/main` (the fast-forward entries name the commits that arrived) and `git diff <old-tip> <new-head>` (the difference is upstream commits, none of them the branch's own); the squashed content is intact when `git diff origin/main <new-head>` lists exactly the files the branch changed. The "tree identical before and after a squash" invariant therefore only holds against the base captured before the rebase, so re-read `origin/main` rather than trusting the sha printed before a long review loop.
