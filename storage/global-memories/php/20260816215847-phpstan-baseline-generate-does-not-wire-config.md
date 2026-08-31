---
date: 2026-08-16
keywords: ["php", "phpstan", "baseline", "types:check", "memory limit"]
trigger-on: ["phpstan-baseline-config"]
---

## PHPStan `--generate-baseline` does not wire the baseline into `phpstan.neon`

Running `vendor/bin/phpstan analyse --generate-baseline` creates `phpstan-baseline.neon` (recording existing errors so the gate passes while new errors still fail) but does NOT add it to the config's `includes:` — you must add `- phpstan-baseline.neon` manually. The generator finishes with "[OK] Baseline generated with N errors" and the next `analyse` still reports the same N errors until the include line exists. Also, `phpstan analyse --memory-limit` default of 256M can crash on large apps; the crash surfaces once the memory issue is resolved by running in a container with more memory. Apply: after `--generate-baseline`, edit `phpstan.neon` includes and re-run `composer types:check` to confirm zero errors.
