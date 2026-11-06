---
date: 2026-11-06
keywords: ["phpunit", "paratest", "missing-results", "memory-limit", "worker-stderr"]
aliases: ["MissingResultsException has no cause", "worker killed silently", "paratest worker died", "unexpected process termination"]
---

## ParaTest hides the worker's fatal error when it reports missing results

When a worker dies without writing its `test_result` file, ParaTest throws `MissingResultsException: One or more workers failed to generate test result files, likely due to unexpected process termination (e.g., out of memory)` — and prints nothing else. The worker's stdout/stderr are captured by Symfony Process and discarded on that path; only the parent's stderr reaches the console. So a worker killed by its own `memory_limit` (which does print `PHP Fatal error: Allowed memory size … exhausted`, but to the worker's stderr) looks identical to a `SIGKILL`, and the "likely out of memory" hint is the only clue you get. Make the death visible by giving the workers a log file through the passthru — `--passthru-php="-d error_log=/tmp/worker-error.log"` — and print that file when the job fails. PHP always logs a fatal to `error_log`, so an **empty** log after a crash is positive evidence of an external `SIGKILL` (kernel OOM), while an entry names the real error. Note the same silence applies to the coverage variant: the clover merge then fails earlier with `MissingResultsException … 'coverage'`, or the parent dies unserializing a worker's coverage file.
