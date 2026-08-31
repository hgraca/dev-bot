---
date: 2026-08-20
keywords: ['shell', 'cross-env', 'npm-script', 'package.json']
trigger-on: ['cross-env-script']
---

## `cross-env VAR=x && cmd` silently drops the env var

In a package.json script, `"test": "cross-env NODE_ENV=test && jest --watch"` does NOT set `NODE_ENV` for jest — the `&&` splits it into two commands, so `cross-env NODE_ENV=test` runs as a no-op and jest executes without the variable. The fix is to drop the `&&`: `"test": "cross-env NODE_ENV=test jest --watch"`. This looks correct at a glance and fails silently (tests may still pass without the var), so when an env var isn't taking effect, grep the scripts for `cross-env ... &&`.
