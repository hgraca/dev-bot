---
date: 2026-11-27
keywords: ["laravel", "phpunit", "env", "postgres", "pest"]
aliases: ["phpunit env override", "force=true", "run pest against postgres"]
---

## phpunit.xml `<env>` is not forced, so the shell wins

An `<env name="DB_CONNECTION" value="sqlite"/>` line in `phpunit.xml` does not override a variable that already exists in the process environment unless it carries `force="true"`. That cuts both ways. `DB_CONNECTION=pgsql php artisan test path` genuinely runs on Postgres, which is how one file can be exercised against real DDL while the rest of the suite stays on sqlite. The trap is the inverse: overriding only `DB_DATABASE` leaves `DB_CONNECTION=sqlite` in force from the file, PHPUnit then creates a sqlite _file_ literally named after the value, the run passes, and nothing about Postgres was tested — a false green discovered only because a stray database file appeared in the checkout. Set every connection variable you mean to change, and assert the driver (bootstrap the app in `php -r` and echo `DB::connection()->getDriverName()`) before trusting the result. Entries written with `force="true"` pin the opposite way and will silently win over the shell.
