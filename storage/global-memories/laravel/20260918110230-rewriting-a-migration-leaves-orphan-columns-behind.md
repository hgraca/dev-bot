---
date: 2026-09-18
keywords: ["laravel", "migrations", "schema-drift", "eloquent-casts"]
trigger-on: ["laravel-migration-rewrite", "migration-filename-unchanged", "orphan-column", "eloquent-cast-missing-column"]
---

## Rewriting a migration under the same filename leaves orphan columns in every database that already ran it

A migration is tracked by filename in the `migrations` table, so editing the file — even deleting a `$table->boolean(...)` line — changes nothing for any database that already applied it. The column stays there forever, while fresh environments built from the current file never get it. The result is silent schema drift *between environments* that no code change reveals: local development (migrated from an earlier revision of the file) has the column, while staging and production (migrated from the shipped revision, or created later) do not.

This bit for real: a leftover `'is_backoffice' => 'boolean'` cast on a model whose column had been removed from its migration during a redesign. `casts()` types an attribute Eloquent *already loaded*; it neither creates nor implies a column. So on the environments without the column, reads returned `null` silently — the attribute is absent from the model, so the cast never fires, and truthiness checks appear to work while `=== false` and `is_bool()` do not — while every write (`$model->is_backoffice = true; $model->save();`, a `where()`, or mass assignment) threw `SQLSTATE[42S22]: Unknown column`. Code touching it passed locally and 500'd in staging.

Two habits prevent this. When removing a column from a migration line, ship a follow-up migration that drops it, so the drift is corrected rather than hidden. And when a model casts a column, confirm that column exists in the current migration set — a cast reads like schema documentation, so a stale one is a signal the schema moved underneath it.
