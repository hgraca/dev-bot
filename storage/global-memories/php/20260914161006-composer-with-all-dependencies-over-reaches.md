---
date: 2026-09-14
keywords: ["php", "composer", "composer-update", "lockfile", "dependency-management"]
trigger-on: ["composer-lock-update", "composer-update-package", "lockfile-out-of-sync"]
---

## `composer update <pkg> --with-all-dependencies` over-reaches; use `--with-dependencies` for a minimal lock update

When one package's constraint changes in `composer.json` (e.g. bumped to `get-e/php-overlay: ^5.11.0`) and its lockfile entry must be re-resolved, `composer update <pkg> --with-all-dependencies` (alias `-W`) lets composer refresh the package's *entire* dependency subtree — in a Laravel app this pulled in ~40 unrelated packages (laravel/framework v13.26→v13.31, symfony/* v8.0→v8.1, monolog, flysystem). `composer update <pkg> --with-dependencies` updates only the package plus its **direct** dependencies, which is normally the full required set: the mandatory cascade (brick/math, brick/money for php-overlay) still resolves, but unrelated top-level packages stay pinned to the lock. Reach for `-W` only when you deliberately want the subtree refreshed. Note that bare `composer update <pkg>` updates *only* the named package and errors if its own dependencies are locked below its requirements — hence `--with-dependencies` is the middle ground. This matters most right after a `git rebase` that reverted `composer.lock` but kept the `composer.json` bump: a targeted `--with-dependencies` update re-syncs the lock with a minimal diff.
