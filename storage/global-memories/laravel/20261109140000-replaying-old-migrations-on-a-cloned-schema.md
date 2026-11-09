---
date: 2026-11-09
keywords: ["laravel", "migration", "max_statement_time", "ALTER", "TTL index"]
trigger-on: ["laravel-migration-replay", "laravel-long-alter", "mongodb-ttl-index-conflict"]
---

## Replaying years of migrations on a cloned schema hits three separate traps

Bringing a fresh environment up to current by restoring a years-old schema and running `php artisan migrate` exposes traps that incremental deploys never see. (1) The get-e `gete` DB connector runs `SET max_statement_time={query_timeout}` and the `laravel` connection pins it to 60 s, so any long `ALTER` dies with `SQLSTATE[70100] … 1317 Query execution was interrupted`; the `mysql` connection has no `query_timeout`, so running the job with `DB_CONNECTION=mysql` lifts the cap without touching code. (2) `ALTER TABLE … ADD INDEX` on a few-hundred-MB table can enter the COPY path and appear hung — MariaDB shows no active query and no `information_schema.innodb_trx` row while PHP blocks on the dead connection; pre-apply it with `ALGORITHM=INPLACE, LOCK=NONE` (seconds instead of never) and record the migration row yourself. (3) Mongo `createIndex` refuses an existing index whose options differ (`code 85`, "An equivalent index already exists with the same name but different options"), so a TTL index created earlier with another `expireAfterSeconds` blocks the migration — drop the index first, the driver will recreate it. Also expect data-level blockers the schema history never met: duplicate values rejecting a new UNIQUE key (regenerate them) and parent rows blocked by `RESTRICT` FKs during a table rebuild (run the ALTER with `SET SESSION foreign_key_checks=0`).
