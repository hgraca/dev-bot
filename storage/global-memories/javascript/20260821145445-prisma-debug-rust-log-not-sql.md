---
date: 2026-08-21
keywords: ["javascript", "prisma", "debug", "logging", "query"]
trigger-on: ["prisma-query-logging", "prisma-debug"]
---

## Prisma DEBUG/RUST_LOG env vars don't reveal SQL — use log: ['query']

Prisma (6.x NAPI engine) does not surface raw SQL via `DEBUG=prisma:*` — that only enables the JS client's `debug`-package output (engine/client lifecycle messages, not query text) — nor via `RUST_LOG` (a no-op for the NAPI engine). The only way to see the actual SQL (e.g. `BEGIN`/`COMMIT`) is the `log: ['query']` constructor option; gate it behind an env var so it's togglable from the manifest without a redeploy: `super({ log: process.env.PRISMA_QUERY_LOG === '1' ? ['query'] : [] })`. Prisma's SQL-comments feature is the alternative that embeds the call site directly into the SQL.
