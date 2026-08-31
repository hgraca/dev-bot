---
date: 2026-08-18
keywords: ["laravel", "migration", "migrator", "phpunit", "DDL"]
trigger-on: ["laravel-migration-test", "migrator-run-test"]
---

## Test publishable migrations via the Migrator, not by calling up()/down()

Laravel's base `Migration` class declares no `up()`/`down()` — anonymous migration files define them inline — so `$migration->up()` on a required migration file is a PHPStan level-max `method.notFound`. Also, ALTER TABLE on MariaDB/MySQL implicitly commits, silently destroying a `DatabaseTransactions` test wrapper (though Laravel's rollBack no-ops safely when transactions hit 0). In PHPUnit tests, run the migration through the real pipeline instead: `$migrator = $this->app->make(Migrator::class); $migrator->run([$migrationFilePath]); … $migrator->rollback([$migrationFilePath]);` and extend `NonTransactionableTestCase` (no transaction trait). `run()`/`rollback()` accept a direct `.php` file path, and rollback only touches migrations matching the passed path, so a single migration can be exercised and cleanly reverted.
