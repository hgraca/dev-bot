---
date: 2026-09-15
keywords: ["php", "rector", "phpstan", "static-analysis", "ci"]
trigger-on: ["rector-ci-check", "static-analysis-exit-code"]
---

## Rector can crash during container boot and still exit 0, making a `--dry-run` gate a false green

`vendor/bin/rector process --dry-run` can die while building its own container — e.g. `Rector\Exception\Reflection\MissingPrivatePropertyException: Property "$container" was not found in "PHPStan\Parser\RichParser"`, caused by a rector/phpstan version mismatch — and still exit with status 0. Any make/CI step that only trusts the exit code then reports success while Rector analysed no files at all, hiding both the crash and whatever regressions it would have caught; the exception text is printed but easily lost in a long log. Harden the gate: capture the output and fail on a crash signature in addition to the exit code, e.g. redirect to a log and `grep -qE "MissingPrivatePropertyException|Fatal error"` before declaring success. Fix the root cause by aligning versions (`rector/rector` together with `phpstan/phpstan`) — never suppress it. Note the exit code alone cannot distinguish a crash from a legitimate finding, since `--dry-run` also exits non-zero when changes are pending.
