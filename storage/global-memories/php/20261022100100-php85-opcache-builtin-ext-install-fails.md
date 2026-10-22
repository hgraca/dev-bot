---
date: 2026-10-22
keywords: ["php", "opcache", "docker-php-ext-install", "php-8.5", "dockerfile"]
trigger-on: ["php-version-upgrade", "dockerfile-php-extensions"]
---

## PHP 8.5 builds OPcache in, so docker-php-ext-install opcache fails the build

PHP 8.5 compiles OPcache statically into the binary and no longer ships it as a shared extension. A Dockerfile that still lists `opcache` in a `docker-php-ext-install` call breaks on the 8.5 base image with `cp: cannot stat 'modules/*'` followed by `make: *** [Makefile:89: install-modules] Error 1` — the extension directory is simply not produced.

Remove `opcache` from the extension list when moving to 8.5. Nothing is lost: `php -m` reports `Zend OPcache` in the stock image, and `docker-php-ext-enable` is not needed for it. Only `opcache.enable_cli` has to be set explicitly if CLI caching matters (it defaults to off).
