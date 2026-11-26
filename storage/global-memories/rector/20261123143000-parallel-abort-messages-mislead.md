---
date: 2026-11-23
keywords: ["rector", "parallel-timeout", "error-count-limit", "diagnostics"]
aliases: ["Could not process some files", "Child process timed out after 120 seconds", "ParallelProcess.php", "system errors count limit of 50"]
trigger-on: ["rector-parallel-abort-diagnosis"]
see: ["rector/20260923201723-02-no-default-vendor-exclusion.md"]
---

## Rector's parallel abort messages name the wrong file and fake the error count

A failed parallel Rector run prints a block that reads as if the scanner walked `vendor/`:

```
[ERROR] Could not process
        "…/vendor/rector/rector/vendor/symplify/easy-parallel/src/ValueObject/ParallelProcess.php" file, due
        to: "Child process timed out after 120 seconds". On line: 96

[ERROR] Could not process some files, due to:
        "Reached system errors count limit of 50, exiting..."
```

Both lines mislead. `ParallelFileProcessor::handleErrorCallable` builds each entry as `SystemError($throwable->getMessage(), $throwable->getFile(), $throwable->getLine())`, so the path shown is the **throwing frame's own source file** — easy-parallel's, not a file under review. And the same callable sets `$reachedSystemErrorsCountLimit = true` unconditionally on the first error, so the "limit of 50" line follows a _single_ child timeout however few errors occurred. Never conclude from this output that `vendor/` is being scanned; check the real file set instead — `storage/cache/static_analysis/rector` should hold zero entries containing `/vendor/`. The actual fault is Rector's job timeout: `RectorConfig::parallel(int $processTimeout = 120, int $maxNumberOfProcess = 32, int $jobSize = 16)` arms a 120s timer per chunk of up to 16 files, so a cold run on a loaded host aborts while an idle one finishes in seconds. Raise only the timeout with `$rectorConfig->parallel(300)` — it re-passes the same default process count and job size, so nothing but the timer changes. `--clear-cache` is the supported way to force the cold path; `rm -rf` on the cache dir is blocked by the guards module.
