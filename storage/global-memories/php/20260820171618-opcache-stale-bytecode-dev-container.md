---
date: 2026-08-20
keywords: ["php", "opcache", "docker", "dev-container", "stale-bytecode"]
trigger-on: ["opcache-stale-bytecode"]
---

## Dev container with opcache.validate_timestamps=0 serves stale bytecode

A PHP dev container whose opcache.ini sets `opcache.validate_timestamps=0` (with `opcache.enable_cli=1` and `opcache.file_cache=/tmp/php-opcache`) compiles each file once and never revalidates — edits to .php files are invisible to every subsequent test run until the cache is flushed. Symptom: `make t`/phpunit keeps failing identically after a code change, while a standalone `php -r` probe of the same logic works. Fix: flush the file cache inside the container (`rm -rf /tmp/php-opcache`) before re-running; the location comes from the `opcache.file_cache` directive in the container's opcache.ini. There may be no Makefile target for it — consider adding one.
