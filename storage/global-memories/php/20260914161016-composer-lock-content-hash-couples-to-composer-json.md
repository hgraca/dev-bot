---
date: 2026-09-14
keywords: ["php", "composer", "composer-lock", "content-hash", "git-fixup"]
trigger-on: ["composer-lock-split-across-commits", "composer-fixup-commit"]
---

## composer.lock's `content-hash` couples it to composer.json — rebuild split lock states with composer, don't stage hunks

`composer.lock` carries a `content-hash` derived from the relevant parts of `composer.json`. When two distinct `composer.json` changes (say a package bump plus a dev-tooling bump) both land in one working-tree `composer.lock`, you cannot cleanly split that file across two atomic commits by staging hunks: the single `content-hash` line belongs to both changes, and hand-picking only the package hunks leaves each intermediate commit with a lockfile whose hash matches neither composer.json state — `composer validate` then fails on it. Deterministic fix: `git restore composer.json composer.lock` back to the base, run only the first change's `composer update/require`, verify `composer validate` passes, commit that lock, then apply the second change with composer and commit the rest. Let composer compute each state's hash; never hand-edit `content-hash`. This is the reliable way to turn one combined lock change into per-package commits (or a `--fixup` targeting the earlier package commit).
