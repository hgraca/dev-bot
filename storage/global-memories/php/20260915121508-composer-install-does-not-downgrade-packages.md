---
date: 2026-09-15
keywords: ["php", "composer", "composer-install", "vendor", "lockfile"]
trigger-on: ["composer-install", "composer-lock-vs-vendor"]
---

## `composer install` never downgrades a package that still satisfies composer.lock

`composer install` reconciles vendor against composer.lock, but when vendor already holds a *newer* version of a package and that version still satisfies the constraint in the lock, it reports "Nothing to install, update or remove" and leaves the newer version in place — it does not downgrade. The symptom misleads badly: after restoring an earlier composer.lock (e.g. `git checkout -- composer.lock`), `composer show <pkg>` and every runtime behaviour still reflect the newer version, so tool output appears to contradict the lockfile. Observed while diagnosing a Rector/PHPStan crash — the lock was restored to `driftingly/rector-laravel` 2.5.0 but vendor still held 2.6.2, and two conclusions (including a code change) were drawn from a vendor state that no longer matched the lock. To force vendor to match the lock, run `composer install` and then confirm with `composer show <pkg>`; if it still disagrees, remove that package's directory or `rm -rf vendor && composer install`. Never infer the installed state from the lockfile — the two can diverge silently.
