---
date: 2026-08-05
keywords: ['docker', 'frankenphp', 'opcache', 'hot-reload']
trigger-on: ['frankenphp-opcache-hot-reload']
---

## FrankenPHP opcache blocks PHP hot reload in dev

FrankenPHP (like Octane) is a long-running PHP process — OPcache caches compiled PHP files in memory. When `opcache.validate_timestamps=0` (production default), code changes are never picked up and the container must be restarted. The fix for dev: mount a dev-specific php.ini override (e.g. `zz-dev.ini`) with `opcache.validate_timestamps=1` and `opcache.revalidate_freq=2` as a volume in compose.yaml, so it loads after the production config. This is separate from the Dockerfile's `COPY` instruction — the volume mount overrides the built-in config at runtime without rebuilding the image.
