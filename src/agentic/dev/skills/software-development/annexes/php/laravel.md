---
name: laravel
description: "Laravel conventions: project structure (Laravel 10), configuration, Eloquent, controllers, validation, authentication, Artisan commands, testing, container entrypoints and queue workers. Read this annex when working with Laravel."
---

# Laravel

## When to Apply

- Writing or modifying Laravel application code
- Working with Eloquent models, migrations, or database queries
- Creating controllers, Form Requests, or route definitions
- Running Artisan commands or creating new files via Artisan
- Writing Laravel-specific tests
- Changing a container entrypoint, queue worker flags, or worker probes

## Annex of `devbot:software-development`

This file is an annex of the `devbot:software-development` hub. Read it only when working with Laravel. For generic craft — code-quality principles, tests-first discipline, commit protocol — see `devbot:software-development`.

## Foundational Context

This is Laravel application. Package versions in `composer.json` — abide by those versions.

This project upgraded from Laravel 10 without migrating to new file structure. This is fine and recommended by Laravel. Follow existing Laravel 10 structure.

### Laravel 10 Structure

- Middleware: `app/Http/Middleware/`
- Service providers: `app/Providers/`
- No `bootstrap/app.php` application configuration:
  - Middleware registration: `app/Http/Kernel.php`
  - Exception handling: `app/Exceptions/Handler.php`
  - Console commands/schedule: `app/Console/Kernel.php`
  - Rate limits: `RouteServiceProvider` or `app/Http/Kernel.php`

## Conventions

- If you see test using "Pest", convert it to PHPUnit.

## Configuration

- Never call `env()` outside `config/*.php` files. Use `Config::` in application code.
- Config files live in `config/` at package root, published via `$this->publishes(...)` in service provider's `boot()` method.

## Do Things Laravel Way

- Use `php artisan make:` commands to create new files (migrations, controllers, models, etc.)
- Use `php artisan list` to discover commands, `php artisan [command] --help` for parameters
- For generic PHP classes: `php artisan make:class`
- Pass `--no-interaction` to all Artisan commands. Pass correct `--options` for expected behavior.

## Database

- Use Eloquent relationship methods with return type hints. Prefer relationships over raw queries.
- Prefer `Model::query()` over `DB::`.
- Prevent N+1 queries with eager loading.
- Use query builder only for very complex operations.
- Laravel 12 allows limiting eagerly loaded records natively: `$query->latest()->limit(10);`
- When modifying column in migrations, include all previously defined attributes — otherwise they are dropped.

### Models

- Casts: use `casts()` method rather than `$casts` property. Follow existing model conventions.
- When creating new models, create factories and seeders. Check `php artisan make:model --help` for options.

### APIs

- Default to Eloquent API Resources and API versioning unless existing routes differ — then follow existing convention.

## Controllers & Validation

- Always use Form Request classes for validation — not inline validation in controllers. Include rules and custom error messages.
- Check sibling Form Requests for array vs string-based validation rules.

## Authentication & Authorization

- Use Laravel's built-in features: gates, policies, Sanctum, etc.

## URL Generation

- Prefer named routes and `route()` function.

## Testing

- Use model factories in tests. Check for factory custom states before manual setup.
- Faker: Use `$this->faker->word()` or `fake()->randomDigit()`. Follow existing `$this->faker` vs `fake()` convention.
- Use `php artisan make:test [options] {name}` for feature tests, `--unit` for unit tests. Most tests should be feature tests.

## Caching

### Cache arrays/scalars only — never objects

`config/cache.php` sets `'serializable_classes' => false` (PHP object-injection hardening). Serializing cache stores (Redis, file, database) read values back with `unserialize($value, ['allowed_classes' => false])`, so **any object stored in the cache comes back as `__PHP_Incomplete_Class`** — arrays and scalars are unaffected.

Symptoms:

- `TypeError: Foo::bar(): Return value must be of type ..., __PHP_Incomplete_Class returned`
- Cached objects that fail their declared types or cannot be used.

Rules:

- Cache plain arrays/scalars only: `->pluck('column')->all()`, `->toArray()`, primitives.
- Rebuild objects on read, outside the cache call: `new Collection(Cache::remember(...))`.
- The rule applies to `Cache::remember()` closures and `Cache::put()` values alike.

Why tests miss it: `phpunit.xml` sets `CACHE_DRIVER=array`, and the array store never serializes — object-caching bugs stay green in unit tests and explode only on serializing stores (Redis in production). When changing anything cached, add a regression test that pins a serializing store:

```php
config()->set('cache.default', 'file');
config()->set('cache.stores.file.path', storage_path('framework/testing/cache'));
```

Incident 2026-09-07: `OptionsFilter::blacklistTransporterIdsFor()` cached an Eloquent `Collection`; the second read within the TTL threw the TypeError above → HTTP 500s on Booking.com/Trip.com estimate flows.

## Container Entrypoint & Queue Workers

The entrypoint (`.docker/*start*.sh`) decides how the worker **process** lives; the pod spec — probes,
`terminationGracePeriodSeconds`, `preStop` — is the other half, and neither works without the other.
Four process-level rules, each fixing a different failure:

- **`exec` every direct branch** — `php-fpm`, kafka consumers, the scheduler. Without it the shell is
  PID 1 and never forwards TERM to its child, so the worker does not drain: it runs until the
  grace-period SIGKILL.
- **Supervise `queue:work` in a restart loop** — the worker must exit on its recycle bound, but the pod
  must not restart. Fork it, restart it in place on that exit, and publish the child pid for a
  liveness probe. Keep a shutdown flag: the worker exits the same way after the supervisor forwards the
  pod's TERM, and a loop that cannot tell a recycle from a shutdown starts a fresh worker during
  termination and runs until the grace-period SIGKILL.
- **Re-`wait` while draining, never poll** — a repeated TERM interrupts `wait`, so drain inside
  `while kill -0 "$pid"; do wait "$pid"; done`. The `wait` is what reaps the child, so the following
  `kill -0` fails and the loop ends; a `kill -0` poll alone spins forever on the zombie.
- **Recycle on `--max-time=1260`, not `--max-jobs`** — `--max-jobs` degenerates on a busy queue: 1000
  jobs at ~48 jobs/s means a full Laravel boot plus the throttle gap every ~20 s. `--memory` still
  bounds growth.

`exec` alone is not enough: the worker still exits on its bound, so the pod still restarts. `core`
measures 66–70 restarts per 23 h that way; `hotels-api` runs `exec` + `--max-jobs=500` with the same
defect.

Pidfile probe contract: it holds the worker pid and is stale across the recycle gap (throttle + boot),
so `failureThreshold × periodSeconds` must exceed that gap — otherwise the probe restarts the pod on
every expected recycle, reintroducing the failure the supervisor removed.

Incident 2026-11-19 (POS-348): `positioning-activities` exited every ~20 s on `--max-jobs=1000`;
kubelet restarted the pod each time, `availableReplicas` flapped, and Argo held the Application's
sync. Reference implementation and shell test: [GET-E/positioning-activities#447](https://github.com/GET-E/positioning-activities/pull/447).

## Do Not

- Create verification scripts or tinker when tests cover that functionality
- Change application dependencies without approval
- Cache objects (Eloquent models, Collections, DTOs) in the shared cache — see [Caching](#caching)

## See also

- `annexes/php/php-rules.md`
- `annexes/php/message-bus.md`
- `devbot:make-tests` skill
