---
date: 2026-10-23
keywords: ["php", "composer", "git-worktree"]
aliases: ["composer update source install worktree", ".git directory is missing"]
trigger-on: ["composer-worktree-vendor", "composer-source-install-update"]
---

## A source-installed vendor dir hardlinked into a fresh worktree breaks `composer update`

A worktree tool that hardlinks `vendor/` from the main checkout copies a **source** install of a VCS package without its usable `.git` directory. `composer update <package>` then fails with `The .git directory is missing from vendor/<vendor>/<package>, see https://getcomposer.org/commit-deps` — it wants to `git pull` an install it cannot inspect, and `--prefer-dist` does not override the decision. Fix: delete `vendor/<vendor>/<package>` in the worktree and let Composer install it fresh (`composer update <package> --prefer-dist`, with a token available so the archive download succeeds). Deleting the worktree's copy is safe: the main checkout's files are separate directory entries pointing at the same inodes.
