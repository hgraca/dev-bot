---
date: 2026-11-17
keywords: ["php", "composer", "composer.lock", "diff"]
aliases: ["published-time noise", "plugin-api-version bump", "lock diff too big"]
trigger-on: ["composer-dependency-bump"]
---

## composer 2.11 adds `published-time` to every lock entry, so a one-package update looks like a rewrite

Running `composer update <vendor>/<pkg>` with composer 2.11 rewrites `"published-time"` into **every** package entry in `composer.lock` and bumps `plugin-api-version` from `2.9.0` to `2.11.0`. A genuinely one-package bump then shows up as 40+ changed entries, which is unreviewable and hides what actually moved.

Strip both after the update: drop the `published-time` keys and restore the committed `plugin-api-version`. Composer ignores the missing key and `composer validate` / `composer install --dry-run` still pass, so the diff collapses to the packages that really changed plus the recomputed `content-hash`. Keep `plugin-api-version` at the value the repo's CI composer writes, or every future update re-adds the same noise.

Two related traps when bumping a single package: `-W` / `--with-all-dependencies` cascades upgrades through the whole dependency tree (a one-line pin can drag in a dozen framework upgrades), and the dev-tools composer plugin may rewrite git-tracked managed files during the run — inspect `git status` and revert anything that is not the dependency change itself.
