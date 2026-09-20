---
date: 2026-09-18
keywords: ["php", "composer", "content-hash", "composer.lock"]
trigger-on: ["composer-lock", "content-hash", "lock-surgery"]
---

## Computing composer.lock's content-hash by hand

When a history rewrite leaves `composer.lock`'s `content-hash` stale and `composer update --lock` cannot run — for example when a full resolve is blocked by a pre-existing conflict such as `roave/security-advisories` versus a pinned `aws/aws-sdk-php` — the hash can be recomputed directly. Take the top-level `name`, `version`, `require`, `require-dev`, `conflict`, `replace`, `provide`, `minimum-stability`, `prefer-stable`, `repositories` and `extra` keys, plus `config.platform` when present, sort those top-level keys, then `md5(json_encode(...))` using PHP's defaults: no whitespace, forward slashes escaped as `\/`, non-ASCII escaped. Verify the implementation by reproducing a known-good pair first — an unchanged `composer.json` must produce the hash already recorded in its lock — before trusting output for a modified file.
