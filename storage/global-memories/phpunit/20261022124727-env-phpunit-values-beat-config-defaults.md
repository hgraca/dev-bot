---
date: 2026-10-22
keywords: ["phpunit", "env", "dotenv", "test-isolation", "config"]
aliases: ["getenv beats config default", "ambient env var in tests", "env() returns stale value in phpunit"]
---

## `.env.phpunit` values override the config defaults your test is asserting

A config test that sets `config('app.env')` to exercise a default and then requires the config file can still see an **ambient** value, because `env()` reads the process environment (via `Illuminate\Support\Env`'s adapters over `$_ENV`, `$_SERVER` and `getenv`), not the config repository. If the repo's `.env.phpunit` defines that variable — very common, e.g. `MESSAGE_BUS_AUDIT_LOG_ENABLED=false` — then `env('X', $default)` returns the `.env.phpunit` value and the default is never exercised. The test passes on a bare worktree (no `.env`) and fails in CI.

`Illuminate\Support\Env::getRepository()->clear($key)` **does not** fix this: on a default Laravel repository the clear is a no-op against `$_SERVER`/putenv for a value that arrived from the environment, so the ambient value still wins.

Neutralise all three sources in `setUp` (and restore in `tearDown`), then set them explicitly for the override case:

```php
unset($_ENV[$key], $_SERVER[$key]);
putenv($key);                 // clear
// ...
$_ENV[$key] = $_SERVER[$key] = 'true';
putenv("$key=true");          // explicit override
```

Verify by running the test three times — with the variable unset, `=false` and `=true` in the process environment (e.g. `docker run -e KEY=false ...`). A config test that is only green with no ambient value is not yet hermetic.
