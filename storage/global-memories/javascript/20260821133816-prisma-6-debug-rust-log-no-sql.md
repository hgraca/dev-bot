---
date: 2026-08-21
keywords: ["javascript", "prisma", "logging", "debug", "rust_log"]
trigger-on: ["prisma-query-logging", "prisma-sql-logging"]
---

## Prisma 6 (NAPI engine): neither DEBUG nor RUST_LOG shows raw SQL — only log:['query'] does

To see the actual SQL Prisma sends to the DB, the only mechanism that works is the `PrismaClient` constructor option `log: ['query']`. The two environment-variable levers both fail silently in Prisma 6.x: `DEBUG=prisma*` only emits the JS _client_'s operations (`prisma:client prisma.model.findFirst({…}`) and never the raw SQL or transaction markers; and `RUST_LOG=sql_query_connector=debug` (or `quaint=debug`) produces **zero output** — the NAPI Rust engine does not route its `tracing` output to the process stderr under `RUST_LOG`. Gate the query log behind an env var so it can be toggled from the manifest without a redeploy: `super({ log: process.env.PRISMA_QUERY_LOG === '1' ? ['query'] : [] })`. `log: ['query']` prints the SQL but not the JS call site. The SQL-comments (sqlcommenter `comments` option) feature is **not available in Prisma 6.x** — it requires Prisma 7 + a driver adapter. To capture the call site on Prisma 6, override `$transaction` in a `PrismaClient` subclass and print `new Error().stack` before delegating: `return (PrismaClient.prototype.$transaction as any).apply(this, args)`.
