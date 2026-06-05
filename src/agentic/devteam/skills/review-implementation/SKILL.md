---
name: review-implementation
description: "Reviews a code changeset against a plan and project conventions. Use this skill whenever reviewing code changes from a developer, after implementation is complete and ready for review."
---

# Skill: Changeset Review

Systematic code review of changeset against architect's plan and project conventions.

## When to Apply

- After developer signals task completion and readiness for review
- When reviewing PR or code changeset before merge

## Review Workflow

Execute these steps in order before writing any review report.

### 0. Run Test Suite

Run test command. Record pass/fail, number of tests, failures. Failing tests are automatic BLOCKER. Complete remaining steps regardless.

### 1. Parameter & Argument Integrity

For every added or modified method:

- Verify every parameter used in method body. Flag parameters silently ignored in favour of hardcoded values.
- Verify call-site arguments match parameter's semantic intent, not just type.

### 2. Dead Code & Orphaned References

When class, method, or interface deleted or renamed:

- Search entire codebase for remaining references (DI bindings, config, architectural rules, baselines, routes, docs).
- Check for orphaned imports and dead container bindings.

### 3. Dependency Wiring Completeness

When constructor or factory signatures change:

- Verify all container bindings, registrations, and factories supply new parameters.
- Verify variadic/collection parameters wired, not silently defaulting to empty.
- Verify new bindings registered in component's own ServiceProvider, not in root AppServiceProvider (unless binding is cross-cutting). Component encapsulation requires each bounded context to own its wiring.

### 4. Import Hygiene

After any file modification:

- No unused imports remaining.
- No missing imports for newly referenced symbols.

### 5. Cross-file Rename Consistency

When any symbol renamed:

- Search all file types (source, config, YAML, JSON, TOML, Markdown, architectural rules, baselines).
- Verify references in comments, doc tags, and string-based references updated.

### 6. Test Assertion Completeness

For every added or modified test method:

- Verify every assertion matches what method name claims.
- Flag any test whose name states ordering, cardinality, or conditional but whose body only asserts existence or non-null.
- Example violation: name says "after" or "before" but body never compares positions.

**Test coverage regression check** — When existing test modified, compare set of assertions before and after:

- If assertions removed or narrowed (e.g. full-row content comparison reduced to header-only), flag as WARNING unless test name also updated to reflect reduced scope.
- Test named `amounts_are_converted_using_billing_rate` that no longer asserts anything about amounts or conversion is BLOCKER — test name makes promise body must keep.
- Fixture files (`*.csv`, `*.json`, `*.xml`, snapshot files) updated in changeset but no longer loaded by any test are dead fixtures — flag as WARNING and require deletion or re-use.
- Verify test classes do NOT import traits already provided by base TestCase (e.g. `RefreshDatabase` when base uses `LazilyRefreshDatabase`). Redundant traits can cause subtle behavior changes.

**Extension dependency guards** — When test uses functions from optional PHP extensions (`pcntl_*`, `posix_*`, `rdkafka_*`, `imagick_*`, etc.):

- Verify that `extension_loaded()` checks cover **all** required extensions, not just primary one. Test using both `pcntl_signal()` and `posix_kill()` must guard both `pcntl` and `posix` — flag missing guard as WARNING.
- Check for functions from secondary extensions easy to miss (e.g. `posix_kill`/`posix_getpid` alongside `pcntl_signal`).

**Global state restoration** — When test modifies global PHP process state (`pcntl_async_signals()`, `pcntl_signal()`, `ini_set()`, `putenv()`, `date_default_timezone_set()`, `error_reporting()`, or similar):

- Verify test captures previous value before modifying and restores in `finally` block.
- Bare restore at end of method body (not wrapped in `finally`) is WARNING — if test fails or throws, restore skipped and subsequent tests run with polluted global state.

**tearDown lifecycle safety** — When `tearDown()` or `tearDownAfterClass()` method performs multiple cleanup steps (e.g. calls external teardown, restores handler stacks, calls `parent::tearDown()`):

- Verify steps wrapped in nested `try/finally` blocks so every cleanup step runs even if earlier one throws.
- `parent::tearDown()` must be in innermost `finally` to guarantee PHPUnit's own cleanup always executes.
- `tearDown()` that calls external method (framework factory, application kernel, etc.) before other cleanup without `try/finally` is WARNING — if external call throws, remaining cleanup skipped and corrupted state cascades into subsequent tests.

### 7. Static Analysis Baseline Hygiene

When `phparkitect.baseline.json`, `phpstan-baseline.neon`, or any other static-analysis baseline file modified:

- Any new entry added is BLOCKER — architecture rule states baselines must not grow (see ARCHITECTURE.md "Do not add issues to static analysis tools baselines").
- Accept only removals. Require developer to fix violation or update architectural rule instead.

### 8. Decorator & Wrapper Integrity

When decorator or wrapper class forwards calls to inner dependency:

- Every parameter of decorated method MUST be forwarded — flag any silently dropped.
- When inner method's signature has de-facto convention parameters not declared in interface (e.g. `$index` on `Queue::pop()`), verify decorator forwards them so inner object's behaviour not silently broken.

### 9. State-Machine Reset Placement

When method maintains mutable state accumulating across calls and resets on condition:

- Verify reset fires on correct branch. Resetting on job-found path (early return) when intent is reset only on completion (null/empty path) is BLOCKER — discards state intentionally accumulated.
- Verify every caller path that should seed accumulator does so before it is consumed. Conditional seed (`if empty → seed`) that leaves accumulator stale when non-empty is BLOCKER.

### 10. Utility Method Abstraction Bypass

When method calls sibling method to reuse logic, verify sibling's internal invariants hold for every call sequence caller produces.

- If sibling has its own state machine, check that caller does not drive it into inconsistent state (e.g. pre-registering side-channel entries then consumed out of order).
- Prefer direct computation over indirect state manipulation when sibling's state machine not designed for external driving.

### 11. N+1 Query Regression

When changeset introduces bulk-load (e.g. `whereIn`, `with()`, eager loading) to avoid per-row queries:

- Search entire flow for any remaining call that lazily loads same relation on individual models (e.g. `$model->relation` inside loop, or called method that accesses `$model->relation` internally).
- Bulk-load that coexists with per-row lazy load of same relation in same pipeline is WARNING — optimization incomplete and N+1 queries still occur.
- Check called methods (not just inline code) — helper like `fromBillingTrip()` may load `$billingTrip->trip` even if handler pre-fetches trips separately.

### 12. `@phpstan-ignore` and Type-Masking

When `@phpstan-ignore` or `@phpstan-ignore-next-line` comment added or already present on modified code:

- Identify what error suppressed and whether indicates genuine type mismatch rather than PHPStan false positive.
- Under `strict_types=1`, passing `string` where `int` declared raises `TypeError` at runtime. Eloquent commonly returns numeric strings for integer columns when attribute lacks cast. Callback typed as `fn (int $id)` applied to plucked integer column is unsafe without cast — flag as WARNING and suggest `fn (string|int $id): T => new T((int) $id)`.
- `@phpstan-ignore` that hides real type mismatch rather than PHPStan false positive is WARNING, not acceptable suppression.

### 13. Primitive Obsession in Commands & Boundaries

When command, query, or controller added or modified:

- Verify constructor parameters use Value Objects when one exists in domain (e.g. `UserId` not `int`, `HotelId` not `int`, `Mailbox[]` not `string[]`).
- Verify controller `authorize()` calls pass VOs to policies, not raw primitives, when VO already constructed in controller.
- Verify policy methods accept corresponding VO type, not primitive.
- Command accepting raw primitive when domain VO exists for that concept is WARNING.

### 14. Hardcoded Configuration Values

When application or domain layer handlers added or modified:

- Flag hardcoded URLs, hostnames, ports, API keys, or environment-dependent strings. These should be injected via constructor + config binding (`giveConfig` or similar).
- Hardcoded values that vary per environment (dev/staging/prod) are WARNING — they break deployment flexibility and testability.
- Pure domain constants (e.g. mathematical formulas, enum values) are not configuration and should remain inline or as class constants.

### 15. Magic Values — Use Class Constants

When handler, service, or domain class uses literal numbers or strings with domain meaning:

- Flag inline magic numbers (e.g. TTL durations, retry counts, thresholds) and magic strings (e.g. email subjects, status labels) that should be class constants.
- Class constants make intent explicit, enable reuse, and simplify testing.
- Magic value used in more than one place is WARNING. Single-use magic value with non-obvious meaning is INFO.

### 16. Kubernetes Manifest Consistency

When changeset includes Kubernetes YAML manifests (any file with `apiVersion` and `kind`):

- When multiple resources share same `apiVersion`/`kind`, verify they have consistent ArgoCD annotations (`sync-wave`, `sync-options`). Inconsistent annotations across resources of same kind is WARNING.
- When resource uses Custom Resource `apiVersion` (not core `v1`, `apps/v1`, `batch/v1`, `networking.k8s.io/v1`, etc.), verify it has `argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true` if CRD installed by another Application in same changeset. Missing this annotation causes ArgoCD dry-run failures on first sync — flag as WARNING.
- When `kustomization.yaml` exists in same directory as new resource file, verify new file listed in `resources:`. Unlisted resource in Kustomize-managed directory will not be synced — flag as BLOCKER.

### 17. PSR-3 Exception Logging

When `catch` block logs via PSR-3 logger method (`->warning()`, `->error()`, `->critical()`, `->alert()`, `->emergency()`):

- Verify context array includes `'exception' => $catchVariable`. PSR-3 spec reserves `'exception'` key so log handlers can extract full stack trace — without it, only message string captured.
- Missing exception object in `->warning()` or `->error()` call inside catch block is WARNING.
- Catch block that logs `$e->getMessage()` but omits `'exception' => $e` is most common pattern to flag.

### 18. PHP Error Suppression Operator

When `@` operator used on any function or method call:

- Flag as WARNING — `@` operator suppresses all PHP errors indiscriminately, hiding potentially important warnings and making debugging difficult.
- Require targeted `set_error_handler`/`restore_error_handler` pair in `try/finally` block instead, so only expected warnings suppressed and unexpected ones remain observable.
- Only acceptable use of `@` is on trivially safe operations where failure immediately checked (e.g. `@unlink()` followed by existence check).

### 19. Log Level Appropriateness

When log statement added or modified in method called repeatedly (worker loops, per-request handlers, queue consumers, scheduled tasks):

- Verify log level appropriate for call frequency. `info` or higher in hot path that fires every iteration generates high-volume logs and cost.
- Routine "nothing happened" messages (e.g. partition empty, no work found, heartbeat) should be `debug` level — flag `info`+ as WARNING.
- Actionable events (message received, error encountered, retry triggered) appropriate at `info` or higher.

## Review Report

Save to `<issue-folder>/REVIEW-YYYY-MM-DD-NNN.md`.

### Template

> # Review Report
>
> **Verdict**: APPROVED | CHANGES REQUESTED | ESCALATED
>
> - **Test Suite** — Pass/fail, test count, failures.
> - **Plan Compliance** — Does implementation match plan? All steps complete? Unauthorized deviations?
> - **Directory Structure** — File layout matches architecture document?
> - **Domain Quality** — Rich models (not anemic)? Value Objects for domain concepts? Classes sealed/final?
> - **Port Contracts** — Typed DTOs? No raw arrays crossing boundaries? Cross-layer exceptions at port level? No transport leaks?
> - **Application Boundary** — DTOs returned (not domain entities) to presentation?
> - **Parameter & Argument Integrity** — Parameters used? Arguments semantically correct?
> - **Dead Code & Orphaned References** — Old references removed across entire codebase?
> - **Dependency Wiring** — Registrations updated for new parameters? Variadic params wired?
> - **Import Hygiene** — No unused or missing imports?
> - **Cross-file Rename Consistency** — All references updated across all file types?
> - **Test Quality** — Descriptive names? Comprehensive coverage? Reusable named test doubles? Assertions match method name claims (ordering, cardinality, conditions)? No coverage regression (assertions not removed or narrowed without updating test name)? No orphaned fixture files? Extension guards cover all required extensions (not just primary)? Global state modifications restored in `finally` blocks? tearDown() methods with multiple cleanup steps wrapped in nested try/finally?
> - **Static Analysis Baseline Hygiene** — No new entries added to any baseline file?
> - **Decorator & Wrapper Integrity** — All parameters forwarded through decorators? De-facto convention params forwarded?
> - **State-Machine Reset Placement** — Resets on correct branch? Every path that should seed accumulator does so?
> - **Utility Method Abstraction Bypass** — Sibling method state machine not driven into inconsistent state?
> - **N+1 Query Regression** — Bulk-loads not undermined by remaining per-row lazy loads in same pipeline (including in called helper methods)?
> - **`@phpstan-ignore` and Type-Masking** — Suppressions masking real type mismatches (e.g. `string` vs `int` under `strict_types=1`) rather than PHPStan false positives?
> - **Primitive Obsession** — Commands, queries, and controller authorize calls use VOs when domain VO exists? Policies accept VOs not primitives?
> - **Hardcoded Configuration** — No hardcoded URLs, hostnames, or environment-dependent values in application/domain handlers?
> - **Magic Values** — Domain-meaningful literals extracted to class constants?
> - **Kubernetes Manifest Consistency** — Same-kind resources have consistent ArgoCD annotations? Custom CRD resources have `SkipDryRunOnMissingResource`? New files listed in `kustomization.yaml`?
> - **PSR-3 Exception Logging** — Catch blocks that log include `'exception' => $e` in context for stack traces?
> - **PHP Error Suppression** — No `@` operator usage? Targeted error handlers used instead?
> - **Log Level Appropriateness** — Hot-path log statements use `debug` for routine "nothing happened" messages?
> - **Code Style** — Symbols imported? No FQCNs inline? Explicit guards? Sealed/final convention?
> - **Role Compliance** — All code changes made by Developer?
> - **Documentation** — Manual config steps documented? Obsolete steps removed?
>
> ## Findings
>
> _If none: "No findings. All checks passed."_
>
> ### Finding <n>: <Title>
>
> - **Severity**: BLOCKER | WARNING | INFO
> - **File path**:
> - **Problem found**:
> - **Why it matters**:
> - **Correct approach**:
>
> ## Tools used
>
> ### SKILLS
>
> List skills used by agent while doing review, or "None."
>
> ### MCP tools
>
> List MCP tools used by agent while doing review, or "None."

### Severity Definitions

- **BLOCKER** — Must fix before merge. Breaks functionality, fails tests, or violates hard architectural rule.
- **WARNING** — Should fix. Violates conventions or likely to cause issues. When in doubt vs BLOCKER, choose BLOCKER.
- **INFO** — Consider fixing. Style or readability improvement with no functional impact.

### Handling No Findings

When verdict APPROVED, still produce full report with every section addressed. Mark each section with "No issues found." This confirms check was performed.
