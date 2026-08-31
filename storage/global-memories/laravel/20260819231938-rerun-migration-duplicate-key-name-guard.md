---
date: 2026-08-19
keywords: ["laravel", "migration", "index", "rerun", "schema"]
trigger-on: ["laravel-migration-rerun", "duplicate-index-name", "schema-hasindex"]
---

## Re-running a Laravel migration that creates an index fails with "Duplicate key name"

`CREATE INDEX` on an already-indexed column throws `Duplicate key name 'failed_jobs_queue_index'` when a migration is re-executed (e.g. a partial previous application, or after a file rename that re-triggers the migration on consumers who already applied the old filename). Guard each index: `if (Schema::hasIndex($table, $name)) { $table->dropIndex($name); }` before the column type change, then re-create the index after — never attempt `createIndex` when the guard's drop was skipped. Two related mechanics: (1) `Migrator::run()` silently skips migrations already recorded in the `migrations` table — to force a re-run in a test, `DB::table('migrations')->where('migration','like','%...%')->delete()` first; (2) renaming a migration FILE makes Laravel treat it as a new pending migration, which is the correct lever for getting already-migrated consumers to apply a new index on an existing table.
