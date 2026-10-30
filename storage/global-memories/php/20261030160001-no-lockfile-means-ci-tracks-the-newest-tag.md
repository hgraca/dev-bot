---
date: 2026-10-30
keywords: ["php", "composer", "lockfile", "vcs-repository"]
aliases: ["no composer.lock", "composer install resolves the latest tag"]
trigger-on: ["composer-lock-management", "private-vcs-dependency"]
---

## A repo without a tracked `composer.lock` re-resolves the newest tag on every CI run

When `composer.lock` is gitignored, CI's `composer install` has nothing to resolve against and picks the newest tag matching the constraint. A fix merged to a private VCS dependency therefore reaches nobody until a new tag exists — bumping the constraint or editing a lockfile is useless, and the failure looks like the consumer repo's bug. Check `git ls-files composer.lock` before diagnosing: `message-bus` and `php-overlay` both run this way, so a `dev-tools` fix required cutting `0.7.28.0` rather than a dependency bump. The trade-off is real — with a lockfile the upgrade is a reviewable commit; without one, every run silently takes whatever tag is newest.
