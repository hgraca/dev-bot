---
date: 2026-08-03
keywords: ['vite', 'cache', 'dev-server', 'hmr']
trigger-on: ['vite-dev-cache', 'vite-304-stale']
---

## Vite dev server serves stale 304 cached modules after restart

After restarting the Vite dev server (e.g. `make down up dev`), the browser may serve stale cached versions of TSX modules. The browser sends `If-None-Match` with a previously cached ETag, and Vite responds 304 — but the cached version predates recent code changes. Incognito works because it has no cache. Hard refresh (Ctrl+Shift+R) sometimes doesn't help if the browser's disk cache is aggressive. Fix: add `headers: { 'Cache-Control': 'no-store' }` to the `server` config in `vite.config.ts`, then restart Vite and do a one-time cache clear. Not a production concern — production builds use content-hashed filenames.
