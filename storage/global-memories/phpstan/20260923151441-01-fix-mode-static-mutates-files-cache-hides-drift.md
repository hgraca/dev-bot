---
date: 2026-09-23
keywords: ["phpstan", "rector", "baseline", "make"]
trigger-on: ["phpstan-baseline-drift", "rector-fix-mode"]
---

## A fixer-mode `make static` mutates unrelated files, and PHPStan's result cache hides baseline drift

When a `make static` target runs Rector and PHP-CS-Fixer in **fix mode** (not `--dry-run`), it rewrites files the current change never touched, so the working tree fills with unrelated modifications — and a `stage_fixed` pre-commit hook can stage them into your commit. Prefer running the checkers in dry-run mode when validating someone else's change.

PHPStan caches per-file analysis, so the first run after those rewrites can reuse a warm cache and report success while a later run on unchanged code invalidates it and fails. The same tree passing then failing looks like flakiness in the change under test and is not — treat it as a cache artifact and re-run before investigating the code.

Separately, `ignore.unmatched` errors ("Ignored error pattern ... was not matched in reported errors") mean the baseline drifted: `phpstan-baseline.neon` still expects errors the current code no longer produces. Before blaming your change, revert your own files to HEAD and re-run the linter — a failure that reproduces on a pristine tree is pre-existing, and the fix is to regenerate or prune the stale entries, never to silence the check.
