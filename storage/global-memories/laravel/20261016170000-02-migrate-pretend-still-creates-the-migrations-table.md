---
date: 2026-10-16
keywords: ["laravel", "artisan", "migrate", "pretend", "migrations table"]
aliases: ["migrate --pretend side effect", "Preparing database Creating migration table"]
trigger-on: ["laravel-migrate-pretend"]
---

## `php artisan migrate --pretend` still creates the `migrations` table

`MigrateCommand::prepareDatabase()` runs **before** the pretend check: when the migration repository does not exist it calls `migrate:install` unconditionally, and `--pretend` only gates the later `loadSchemaState()` call. So on a database that has never been migrated, `migrate --pretend` prints its SQL plan and **leaves a real `migrations` table behind** ("Preparing database / Creating migration table ... DONE" in its output is the tell). Treat it as a write, not a pure dry run: it is safe for previewing pending migrations once the repository already exists, but against a never-migrated or production database it is not side-effect-free.
