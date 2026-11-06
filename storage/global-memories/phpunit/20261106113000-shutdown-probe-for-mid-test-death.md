---
date: 2026-11-06
keywords: ["phpunit", "shutdown-handler", "error_get_last", "get_cfg_var", "set_time_limit"]
aliases: ["Premature end of PHP process", "process died mid-test", "shutdown probe", "unknown test process death"]
---

## Use a shutdown probe to find why a PHPUnit process died mid-test

`Fatal error: Premature end of PHP process when running <test>` is printed by PHPUnit's `ShutdownHandler`, which sets that message around each test and, if the process shuts down while it is still set, prints it and calls `exit(2)`. It fires for a fatal error **and** for an explicit `exit()` — but says nothing about which. Under paratest the same death is worse: the worker's stderr is discarded and the run fails with a generic `MissingResultsException … test_result`, so the two look unrelated.

Find the real reason by prepending a probe — `php -d auto_prepend_file=/tmp/probe.php …` — where the probe registers a shutdown function logging `error_get_last()`, `memory_get_peak_usage(true)`, `ini_get('memory_limit')` and `ini_get('max_execution_time')`. `error_get_last()` names the fatal verbatim even when the message never reaches the job log (seen: `Maximum execution time of 1200 seconds exceeded`). Two facts make the probe interpretable: `get_cfg_var()` returns the value from php.ini/`-d` **ignoring** any later `ini_set`, which is exactly what a restore step needs; and `set_time_limit()` writes the `max_execution_time` ini value as well as resetting the timer (verified `1200 → 0 → 600`), so it is a valid restore for code that used `ini_set`.
