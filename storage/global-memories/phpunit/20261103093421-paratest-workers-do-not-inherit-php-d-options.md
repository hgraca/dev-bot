---
date: 2026-11-03
keywords: ["phpunit", "paratest", "pcov", "passthru-php", "coverage"]
aliases: ["paratest -d ignored", "pcov.directory workers", "worker ini overrides"]
trigger-on: ["paratest-coverage-config"]
---

## ParaTest workers do not inherit the parent's -d options

ParaTest's WrapperRunner spawns each worker as a fresh `php` process, so a `-d` option given to the parent (`php -d pcov.directory=… vendor/bin/paratest`, or `php -d … artisan test --parallel`) never reaches the workers. Only `--passthru-php` is forwarded: WrapperRunner merges `$options->passthruPhp` into the worker command line. Pass worker-level ini overrides through it, quoting as ParaTest's help shows: `--passthru-php="'-d' 'pcov.directory=/path/to/project'"` (the value is shell-parsed and split into argv). This fails silently in the worst way: workers fall back to php.ini or to PCOV's `pcov.directory` auto-detection, so a coverage job keeps producing a report that looks fine while covering the wrong tree. PCOV auto-detection looks for `src`, then `lib`, then `app` in the worker's CWD — a repository with a root `lib/` therefore instruments only `lib/` and reports near-zero coverage for `app/`.
