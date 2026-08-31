---
date: 2026-08-21
keywords: ['javascript', 'prisma', 'moduleFormat', 'commonjs', 'driver-adapter']
trigger-on: ['prisma-7-upgrade', 'prisma-esm-migration', 'prisma-validator', 'prisma-client-generator']
---

## Prisma 7 does NOT require an ESM conversion — `moduleFormat` emits CommonJS (supersedes the earlier ESM-only note)

The `prisma-client` generator supports a `moduleFormat` option and **infers it from `tsconfig.json` `module`**: a `module: "commonjs"` tsconfig yields CommonJS output with no `"type": "module"`, no `module: ESNext`, and no `.js` import-extension sweep. Verified on a NestJS 11 CommonJS app (driver-service, 2026-08-21): only the generator block, `prisma.config.ts`, the driver adapter, and the import paths change. Setting `moduleFormat = "cjs"` explicitly makes it deterministic. What still holds from the earlier note: `prisma-client` generator requires an explicit `output` (client moves out of `node_modules` — every `@prisma/client` import changes to the generated path), `new PrismaClient({ adapter })` is mandatory (driver adapter per DB; MariaDB → `@prisma/adapter-mariadb` + `mariadb` driver), `prisma.config.ts` holds the datasource URL, and `db push`/`migrate`/postinstall no longer auto-run `prisma generate` — build scripts must call it explicitly.

## v7 API surface changes that break a v6 codebase

- **`Prisma.validator<T>()({...})` is removed** — replace with `{...} satisfies T`. Note: prettier < 2.8.0 cannot parse the `satisfies` operator (TS 4.9, Nov 2022); bump prettier to >= 2.8.8 or lint/format breaks.
- **`PrismaPromise` is no longer a top-level export** of the generated client — it lives under the `Prisma` namespace (`Prisma.PrismaPromise`).
- **`@prisma/client` root entry is gone** — importing `PrismaClient`/types from `'@prisma/client'` fails at runtime; import from the generated output (`<output>/client`).
- **`PrismaClientKnownRequestError` is no longer exported from `@prisma/client/runtime/library`** — use `Prisma.PrismaClientKnownRequestError` from the generated client.
- **The v7 CLI loads `.env` itself** before evaluating `prisma.config.ts` (verified: `prisma --version` prints "Environment variables loaded from .env"), so no `import 'dotenv/config'` is needed in the config file.
- Config shape (7.9.x): `import { defineConfig, env } from '@prisma/config'` with `datasource: { url: env('DATABASE_URL'), shadowDatabaseUrl: env('SHADOW_DATABASE_URL') }`; `env()` throws if the variable is unset.
