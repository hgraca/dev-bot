---
date: 2026-09-09
keywords: ["php", "symfony-process", "ini", "subprocess", "date.timezone"]
trigger-on: ["php-ini-env-interpolation", "symfony-process-subprocess-stdout"]
---

## PHP startup warning pollutes subprocess stdout when ini interpolates a stripped env var

Spawning a PHP CLI child (`new Process([PHP_BINARY, base_path('artisan'), ...])`) from a web SAPI (FPM/artisan serve) does NOT inherit the container's full environment — web workers strip env vars. When the container's `conf.d/overrides.ini` contains `date.timezone=${DATE_TIMEZONE}`, the child php reads the empty var at startup and prints `PHP Warning: Invalid date.timezone value ''` to **stdout** before the script runs. If you parse the child's stdout as structured data (JSON catalog, etc.), the parse fails with a confusing "invalid JSON" error while the same command run directly in a shell works fine.

Root cause is easy to miss: output length differs by ~90 bytes and the prefix is a warning line. Fix: pass the needed env explicitly to the Process constructor — `new Process($cmd, null, ['DATE_TIMEZONE' => (string) config('app.timezone')])` — Symfony Process merges constructor env over defaults. Hit in the GET-E backoffice Run-command page (web-spawned `php artisan get-e:command-catalog`); direct CLI runs were clean, only the HTTP-spawned child warned.
