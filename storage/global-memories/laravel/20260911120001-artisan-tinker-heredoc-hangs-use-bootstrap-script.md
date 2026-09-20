---
date: 2026-09-11
keywords: ["laravel", "artisan", "tinker", "explain", "docker"]
trigger-on: ["artisan-tinker", "explain-query-plan", "container-script-execution"]
---

## Piping a heredoc into `php artisan tinker` hangs — run app code via a standalone bootstrap script instead

Feeding a multi-line heredoc to `php artisan tinker` (e.g. `docker compose exec -T app php artisan tinker <<'PHP' … PHP`) does **not** run-and-exit: PsySH stays in interactive mode waiting for more input, so the command never returns (observed hanging until a 180 s timeout, no output). Tinker is fine for `--execute="…"` one-liners, but not for scripted multi-line app code.

Reliable alternative — a standalone script that boots the framework itself:

```php
<?php
require '/app/vendor/autoload.php';                 // container path
$app = require '/app/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
// … app code (facades, container resolution, models) works normally …
```

Two practical notes: (1) the script must live **inside the project directory** (e.g. `storage/app/`) because the container only mounts the project — a host `/tmp` path is invisible to `docker exec`; delete it afterwards. (2) To `EXPLAIN` a query an app class builds, resolve that class through the container so its bindings apply (`app(TripPricesBillingQueryBuilder::class)` picks up `->needs(CarbonImmutable::class)->give(...)`), then `$q->toSql()` plus `DB::select('EXPLAIN '.$sql, $q->getBindings())` — this reproduces the exact SQL/bindings the app would run, without hand-copying it.
