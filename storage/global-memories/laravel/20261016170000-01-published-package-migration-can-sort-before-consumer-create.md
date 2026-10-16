---
date: 2026-10-16
keywords: ["laravel", "migration", "vendor publish", "ordering", "failed_jobs"]
aliases: ["migration runs before its table exists", "vendor:publish migration timestamp"]
trigger-on: ["laravel-migration-ordering", "vendor-migration-publish"]
---

## A published package migration can run before the consumer's own create-table

`php artisan vendor:publish --tag=<pkg>-migrations` copies a package migration keeping the package's own filename, so its timestamp is whatever the package chose — often a fixed early date. Laravel orders migrations purely by filename, so when the consumer's `create_<table>` migration is dated **later**, the published migration runs first and fails with `SQLSTATE[42S02] ... Table '<db>.<table>' doesn't exist` — a fresh CI or `migrate:fresh` database surfaces it immediately. Worked example: the get-e message-bus ships `2026_01_01_000001_optimize_failed_jobs_table.php`, which breaks any consumer whose `create_failed_jobs_table` post-dates 2026-01-01 (audit-log's is `2026_03_24_175508`). Fix: rename just the published copy to a timestamp that sorts after the table's create migration — the org precedent is to date it to the consumer's then-current date (hotels-api/core use `2026_08_20_...`); the content stays byte-identical and only the filename moves. When publishing into several consumers, check **each** one's create-migration timestamp first: a create migration existing somewhere in the folder is not enough, it must sort before the published one.
