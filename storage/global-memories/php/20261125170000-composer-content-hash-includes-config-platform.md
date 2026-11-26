---
date: 2026-11-25
keywords: ["php", "composer", "content-hash", "config-platform", "composer-lock"]
trigger-on: ["composer-platform-pin", "composer-lock-hash", "offline-composer-update"]
---

## `composer.lock`'s content-hash covers `config.platform`, so bumping the platform pin invalidates it

Changing `composer.json`'s `config.platform.php` makes the lock stale ("The lock file is not up to date with the latest changes in composer.json") even though no dependency changed, and `composer validate --strict` reports it. `composer update --lock` is the supported fix, but it still initialises every `repositories` entry — so with private VCS repositories it needs network and SSH access and fails inside a bare container (`Host key verification failed`, `Bad owner or permissions on /root/.ssh/config`).

When that path is unavailable, the hash can be reproduced offline: `Composer\Package\Locker::getContentHash($composerJsonContents)` is a public static. Its input is the JSON of `name, version, require, require-dev, conflict, replace, provide, minimum-stability, prefer-stable, repositories, extra` plus `config.platform` (only that sub-key of `config`), keys sorted, `md5` of PHP's `json_encode` with options `0` — so slashes escaped as `\/` and non-ASCII as `\uXXXX`. Validate the reimplementation by reproducing the *old* hash from the unmodified file first; if it matches, the new hash is trustworthy. Also mirror the value into the lock's `platform-overrides` block.
