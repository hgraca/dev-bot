---
date: 2026-09-18
keywords: ["php", "composer", "with-all-dependencies", "lock"]
trigger-on: ["composer-update", "composer-partial-update"]
---

## `composer update <pkg> --with-all-dependencies` re-resolves and upgrades the whole transitive tree

A targeted `composer update <pkg>` normally leaves every other locked version alone, but adding `-W`/`--with-all-dependencies` lets composer update the listed packages' entire dependency closure. Adding an instrumented package that depends on `illuminate/*` therefore bumped 55 unrelated packages (laravel/framework 12.50 -> 12.69, every symfony component) in `composer.lock`. Always diff the resulting lock against the previous one by package name and version before committing, and drop `-W` unless a specific transitive conflict actually requires it — the count of added/removed/version-changed packages should be small and explainable.
