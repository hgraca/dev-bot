---
date: 2026-10-23
keywords: ["php", "composer", "preferred-install"]
aliases: ["preferred-install dist", "composer source fallback"]
trigger-on: ["composer-preferred-install", "private-vcs-package-install"]
---

## `preferred-install: dist` turns off Composer's source fallback, so private VCS packages need a token

Composer's default prefers dist but falls back to source when the archive cannot be fetched. Pinning `"preferred-install": "dist"` in `config` removes that fallback: for a private `vcs` package the dist URL is a GitHub zipball, so without a GitHub token (`COMPOSER_AUTH` or `~/.config/composer/auth.json`) the run dies with `The "https://api.github.com/repos/<org>/<repo>/zipball/<sha>" file could not be downloaded (HTTP/2 404)` — a 404, not a 401, because GitHub hides private repositories from unauthenticated requests. Reinstalling from source over SSH works, but only once the pin is gone.
