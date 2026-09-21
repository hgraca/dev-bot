---
date: 2026-09-21
keywords: ["php", "composer", "composer-lock", "dry-run", "vendor"]
trigger-on: ["composer-update", "composer-lock-sync"]
---

## `composer update --dry-run` lists operations against the installed vendor dir, not the lock

When `vendor/` is stale (after a rebase, a long-idle checkout, or a branch switch), `composer update <pkg> --dry-run` prints `Upgrading X (old => new)` lines measured from the packages actually installed in `vendor/composer/installed.json`, not from the versions pinned in `composer.lock`. A repo whose lock already contains the newer versions therefore appears to want dozens of unrelated package upgrades when the true lock delta is only the packages you named — the left-hand side of `(a => b)` is "what is installed", the right-hand side is "what will be resolved". Do not abandon a targeted update because the dry-run looks terrifying: run it, then read `git diff composer.lock` to see the real effect. The lock file is the only source of truth here.
