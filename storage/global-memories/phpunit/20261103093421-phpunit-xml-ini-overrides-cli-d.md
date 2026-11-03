---
date: 2026-11-03
keywords: ["phpunit", "memory_limit", "phpunit.xml", "coverage-merge"]
aliases: ["phpunit.xml ini overrides -d", "coverage merge out of memory"]
trigger-on: ["phpunit-coverage-config"]
---

## phpunit.xml ini entries override CLI -d

PHPUnit applies the `<php><ini>` entries from phpunit.xml at bootstrap, so they win over `-d` flags passed on the command line. `php -d memory_limit=8G vendor/bin/paratest …` (or `-d` on `artisan test`) is therefore ignored when phpunit.xml declares `<ini name="memory_limit" value="4G"/>`, and the parent process that merges the workers' coverage data still dies at the phpunit.xml limit with "Allowed memory size … exhausted". Raise the limit in phpunit.xml (it is only a cap, not an allocation), or rewrite the value before the run. The trap generalises to every `<ini>` the config sets; `pcov.directory` is the exception in the other direction because it is SYSTEM/PERDIR and cannot be set at runtime — only php.ini or `--passthru-php` reaches it.
