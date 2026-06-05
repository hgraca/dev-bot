---
date: 2026-06-22
keywords: ["docker", "composer", "dist-cache", "prefer-source"]
trigger-on: ["composer-in-docker-container"]
---

## Composer dist cache directory not writable in Docker containers

When running `composer require` or `composer install` inside a PHP Docker container, the dist cache directory `/.composer/cache/files/` may not be writable, causing "Failed to download X from dist: ... does not exist and could not be created". Fix: pass `--prefer-source` to `composer install` to clone packages from Git instead of downloading dist archives, avoiding the cache entirely. Alternatively, ensure the cache directory is writable via volume mount or Dockerfile `RUN mkdir -p /.composer/cache/files && chmod 777 /.composer/cache/files`.
