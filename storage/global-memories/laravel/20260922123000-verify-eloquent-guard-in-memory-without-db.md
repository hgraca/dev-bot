---
date: 2026-09-22
keywords: ["laravel", "eloquent", "observer", "phpunit", "verification"]
trigger-on: ["laravel-test-suite-unrunnable-locally"]
---

## Verify an Eloquent observer or model guard in-memory when the test suite cannot run locally

When the phpunit suite is blocked in an environment — here every `Tests\TestCase` run dies in `setUp()` at `Redis::flushdb()` with `RedisClusterException`, so no unit test of a model-touching class can execute — a guard's behaviour can still be proven without the database or Redis by bootstrapping the console kernel and driving the code directly: `$app = require 'bootstrap/app.php'; $app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();`, then build models with `forceFill([...])`, set `$model->exists = true`, and attach relations with `setRelation(...)` so relation reads never reach the DB — an empty collection makes a vacuous `contains()` behave exactly as production does. The one trap is `wasChanged()`, which reads the protected `Model::$changes` that only `save()` populates; set it by reflection, e.g. `(new ReflectionProperty(Model::class, 'changes'))->setValue($model, ['driver_id' => 2])`. Run the script inside the app container (`docker exec <app> php /app/<script>.php`). This turns "I believe the guard returns early" into a printed truth table — and it identified which of five factory-drawn values break the code path, which is what made the fix provable rather than plausible.
