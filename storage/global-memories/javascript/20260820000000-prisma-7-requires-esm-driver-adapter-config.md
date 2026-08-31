---
date: 2026-08-20
keywords: ['javascript', 'prisma', 'esm', 'driver-adapter', 'node']
trigger-on: ['prisma-7-upgrade', 'prisma-esm-migration']
---

## Prisma 7 is a major ESM-required migration, not a version bump

> **SUPERSEDED** (2026-08-21) by `javascript/20260821180000-prisma-7-commonjs-moduleformat-and-migration-gotchas.md` — the `prisma-client` generator infers `moduleFormat` from tsconfig `module`; a CommonJS app stays CommonJS, no ESM conversion required. The rest (driver adapter, `prisma.config.ts`, explicit output, no auto `generate`) still applies.

Upgrading Prisma 6 → 7 is not `yarn add prisma@latest`. Prisma 7 ships ESM-only and requires: `"type": "module"` + tsconfig `module: ESNext` / `moduleResolution: bundler` (a CommonJS app must be converted, including `.js` extensions on relative imports); the `prisma-client-js` generator → `prisma-client` with a required `output` path (client moves out of `node_modules`, so every `@prisma/client` import changes); a driver adapter for every database (MySQL → `@prisma/adapter-mariadb`, instantiated via `new PrismaClient({ adapter })`); a `prisma.config.ts` at repo root (datasource `url` moves out of `schema.prisma`); explicit `dotenv` loading (no auto `.env`); and `db push` / `migrate dev` no longer auto-run `prisma generate`. Read the official "Upgrade to v7" guide before attempting — for a CommonJS NestJS/Express app this is a large multi-part migration, not a dependency bump.
