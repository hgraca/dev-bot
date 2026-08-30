---
name: devbot:review-implementation
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
- Verify new bindings registered in the component's own wiring module, not in the root/global wiring (unless binding is cross-cutting). Component encapsulation requires each bounded context to own its wiring.

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
- Verify test classes do NOT import traits/mixins already provided by the base test class. Redundant traits can cause subtle behavior changes.

### 7. Decorator & Wrapper Integrity

When decorator or wrapper class forwards calls to inner dependency:

- Every parameter of decorated method MUST be forwarded — flag any silently dropped.
- When inner method's signature has de-facto convention parameters not declared in interface (e.g. `$index` on `Queue::pop()`), verify decorator forwards them so inner object's behaviour not silently broken.

### 8. State-Machine Reset Placement

When method maintains mutable state accumulating across calls and resets on condition:

- Verify reset fires on correct branch. Resetting on job-found path (early return) when intent is reset only on completion (null/empty path) is BLOCKER — discards state intentionally accumulated.
- Verify every caller path that should seed accumulator does so before it is consumed. Conditional seed (`if empty → seed`) that leaves accumulator stale when non-empty is BLOCKER.

### 9. Utility Method Abstraction Bypass

When method calls sibling method to reuse logic, verify sibling's internal invariants hold for every call sequence caller produces.

- If sibling has its own state machine, check that caller does not drive it into inconsistent state (e.g. pre-registering side-channel entries then consumed out of order).
- Prefer direct computation over indirect state manipulation when sibling's state machine not designed for external driving.

### 10. N+1 Query Regression

When changeset introduces bulk-load (e.g. `where-in`, eager loading) to avoid per-row queries:

- Search entire flow for any remaining call that lazily loads same relation on individual records (e.g. `record.relation` inside loop, or called method that accesses `record.relation` internally).
- Bulk-load that coexists with per-row lazy load of same relation in same pipeline is WARNING — optimization incomplete and N+1 queries still occur.
- Check called methods (not just inline code) — helper like `fromBillingTrip()` may load `billingTrip.trip` even if handler pre-fetches trips separately.

### 11. Primitive Obsession in Commands & Boundaries

When command, query, or controller added or modified:

- Verify constructor parameters use Value Objects when one exists in domain (e.g. `UserId` not `int`, `HotelId` not `int`, `Mailbox[]` not `string[]`).
- Command accepting raw primitive when domain VO exists for that concept is WARNING.

### 12. Hardcoded Configuration Values

When application or domain layer handlers added or modified:

- Flag hardcoded URLs, hostnames, ports, API keys, or environment-dependent strings. These should be injected via constructor + config binding.
- Hardcoded values that vary per environment (dev/staging/prod) are WARNING — they break deployment flexibility and testability.
- Pure domain constants (e.g. mathematical formulas, enum values) are not configuration and should remain inline or as class constants.

### 13. Magic Values — Use Class Constants

When handler, service, or domain class uses literal numbers or strings with domain meaning:

- Flag inline magic numbers (e.g. TTL durations, retry counts, thresholds) and magic strings (e.g. email subjects, status labels) that should be class constants.
- Class constants make intent explicit, enable reuse, and simplify testing.
- Magic value used in more than one place is WARNING. Single-use magic value with non-obvious meaning is INFO.

### 14. Log Level Appropriateness

When log statement added or modified in method called repeatedly (worker loops, per-request handlers, queue consumers, scheduled tasks):

- Verify log level appropriate for call frequency. `info` or higher in hot path that fires every iteration generates high-volume logs and cost.
- Routine "nothing happened" messages (e.g. partition empty, no work found, heartbeat) should be `debug` level — flag `info`+ as WARNING.
- Actionable events (message received, error encountered, retry triggered) appropriate at `info` or higher.

### 15. Return-Type Contraction Safety

When proposing a return-type or parameter-type narrowing (in a review recommendation or the reviewed change):

- Verify every runtime branch — including pass-through, fallback, early-return, and defensive-escape-hatch paths — can produce a value assignable to the proposed type. A narrowing that excludes a legitimate branch is WARNING.
- Grep existing callers and tests for values that would violate the proposed type (e.g. custom middleware passed through unchanged when only interface types are declared).
- If the narrowed type breaks a used runtime path (confirm by running the test suite), it is BLOCKER — recommend the broader type with both outcomes documented instead.

## Recurring issue types

Check the changeset against these issue types distilled from past reviews. Report a finding when one applies, even if the code "works" in the happy path. Each type names the check and the expected property.

### Generic

Issue types that apply regardless of technology stack.

1. **TOCTOU / concurrent modification** — after an external/network call, **re-read (with lock) and verify the input still matches** before persisting; never write a stale model captured before the call.
2. **Security/availability invariants for config-like entities** — an entity must not be routable/usable before it is fully valid; when old credentials are kept during a migration, block routing if the **security context changed**; represent "ready" as persisted derived state, not just an `enabled` flag; clearing valid fields must not take a working system offline.
3. **Migration correctness** — `down()` must restore the **exact prior schema** (including nullability/index changes); run precondition checks **before destructive operations** (MySQL DDL commits per statement); document intentional asymmetry.
4. **API contract round-trip** — every field required by a request must appear in the response representation (clients cannot round-trip otherwise); computed flags must handle **null vs empty** explicitly; cover with response tests.
5. **Documentation must match implementation** — verify docs against the code: failure semantics (what retries vs fails immediately), external endpoint formats (official, not remembered), configuration behaviour. A doc that contradicts the code is a finding.
    - Code comments and docblocks are docs too: a docblock that contradicts the implementation (e.g. says OPTIONS is included while the code removes it), or a **duplicated stale docblock** left behind an edit, is a finding.
6. **Architecture/design smells** — ports named by domain/area (not by implementation); API inputs reduced to what cannot be derived; no duplicated output or duplicated invariants (single source of truth); queries/logic in intent-named private methods; **compare values before mutating** them; check mutation order (comparing post-mutation values is always equal).
7. **Atomic commit structure** — one logical change per commit; migration-only commits; related cleanup grouped with its change; unrelated changes not bundled.
8. **Configuration & rollout** — only non-default config values should be specified (do not replicate package defaults); env switches/flags must be safe for fresh environments (provisioning must be part of the rollout, or the switch stays off).
9. **Per-request performance** — request-path code must not do work proportional to a global structure per request:
    - Do not scan the full route collection (hundreds of routes × regex) per fallback/404 request — use the framework's compiled matcher.
    - Keep synchronous waits (e.g. Kafka `flush()`, external calls) short for request-path observers/loops; a 10s per-call stall on outage exhausts workers. Long delivery/retry windows belong in a background/outbox path, and the config comment must state which is which.
10. **Deployment/queue rollout compatibility** — deleting a queued job class breaks payloads already waiting/retrying in the queue (they must unserialize the old FQCN): keep a **compatibility shim** class delegating to the new implementation until the queue retention window elapses (note the removal date in the class), or document an explicit drain/migration rollout.

### Technology-specific

Apply the section for each technology the project uses. Each list merges issue types distilled from past reviews with technology-specific pitfalls of the generic checks above.

#### PHP

1. **Untrusted remote input (SSRF & derived-value validation)** — when code fetches or parses external URLs/metadata:
    - Enforce the URL **scheme (https)** at the adapter layer, not only in request validation (async/internal paths bypass validation).
    - Resolve and validate **all A + AAAA records** are public (private/loopback/link-local/reserved) **before** connecting; pin the validated address for the request and **disable redirects** (or validate every hop). DNS-rebinding defeats a resolve-then-connect check that does not pin.
    - Bound the response size (write callback, not unbuffered `CURLOPT_RETURNTRANSFER`) so a streaming endpoint cannot exhaust memory.
    - Validate every value parsed from the external document **before persisting** (format, length vs column size, scheme, count). Fail loudly rather than silently dropping/truncating trusted data.
    - Verify third-party API contracts against the installed code: callback **signatures** (e.g. libcurl passes the handle first), **byte counts** vs character counts in byte-oriented APIs, option value formats (e.g. IPv6 literals must be bracketed in `CURLOPT_RESOLVE`).
2. **Static Analysis Baseline Hygiene** — when a PHP static-analysis baseline file (`phparkitect.baseline.json`, `phpstan-baseline.neon`, or similar) is modified:
    - Any new entry added is BLOCKER — architecture rule states baselines must not grow (see ARCHITECTURE.md "Do not add issues to static analysis tools baselines").
    - Accept only removals. Require developer to fix violation or update architectural rule instead.
3. **`@phpstan-ignore` and Type-Masking** — when `@phpstan-ignore` or `@phpstan-ignore-next-line` comment added or already present on modified code:
    - Identify what error suppressed and whether indicates genuine type mismatch rather than PHPStan false positive.
    - Under `strict_types=1`, passing `string` where `int` declared raises `TypeError` at runtime. Eloquent commonly returns numeric strings for integer columns when attribute lacks cast. Callback typed as `fn (int $id)` applied to plucked integer column is unsafe without cast — flag as WARNING and suggest `fn (string|int $id): T => new T((int) $id)`.
    - `@phpstan-ignore` that hides real type mismatch rather than PHPStan false positive is WARNING, not acceptable suppression.
    - **Do NOT declare an existing `@phpstan-ignore` dead without verification.** Inspect the _installed_ vendor stubs for the suppressed call (`@param`/`@psalm-param`/`@phpstan-param` constraints) and run PHPStan with the referenced dependency actually installed. A suppression satisfying a stub-level constraint stricter than the raw PHP signature (e.g. `non-empty-string`, enum-like unions such as `0|1|2|3|4`) is a REAL suppression — proposing its removal without that verification is a false finding.
    - An `argument.type` error surfacing only when a dependency is missing (`class.notFound`) does NOT prove an annotation is dead — it proves the dependency was never installed.
4. **Extension Dependency Guards** — when test uses functions from optional PHP extensions (`pcntl_*`, `posix_*`, `rdkafka_*`, `imagick_*`, etc.):
    - Verify that `extension_loaded()` checks cover **all** required extensions, not just primary one. Test using both `pcntl_signal()` and `posix_kill()` must guard both `pcntl` and `posix` — flag missing guard as WARNING.
    - Check for functions from secondary extensions easy to miss (e.g. `posix_kill`/`posix_getpid` alongside `pcntl_signal`).
5. **Global State Restoration** — when test modifies global PHP process state (`pcntl_async_signals()`, `pcntl_signal()`, `ini_set()`, `putenv()`, `date_default_timezone_set()`, `error_reporting()`, or similar):
    - Verify test captures previous value before modifying and restores in `finally` block.
    - Bare restore at end of method body (not wrapped in `finally`) is WARNING — if test fails or throws, restore skipped and subsequent tests run with polluted global state.
6. **tearDown Lifecycle Safety** — when `tearDown()` or `tearDownAfterClass()` method performs multiple cleanup steps (e.g. calls external teardown, restores handler stacks, calls `parent::tearDown()`):
    - Verify steps wrapped in nested `try/finally` blocks so every cleanup step runs even if earlier one throws.
    - `parent::tearDown()` must be in innermost `finally` to guarantee PHPUnit's own cleanup always executes.
    - `tearDown()` that calls external method (framework factory, application kernel, etc.) before other cleanup without `try/finally` is WARNING — if external call throws, remaining cleanup skipped and corrupted state cascades into subsequent tests.
7. **PSR-3 Exception Logging** — when `catch` block logs via PSR-3 logger method (`->warning()`, `->error()`, `->critical()`, `->alert()`, `->emergency()`):
    - Verify context array includes `'exception' => $catchVariable`. PSR-3 spec reserves `'exception'` key so log handlers can extract full stack trace — without it, only message string captured.
    - Missing exception object in `->warning()` or `->error()` call inside catch block is WARNING.
    - Catch block that logs `$e->getMessage()` but omits `'exception' => $e` is most common pattern to flag.
8. **Error Suppression Operator** — when `@` operator used on any function or method call:
    - Flag as WARNING — `@` operator suppresses all PHP errors indiscriminately, hiding potentially important warnings and making debugging difficult.
    - Require targeted `set_error_handler`/`restore_error_handler` pair in `try/finally` block instead, so only expected warnings suppressed and unexpected ones remain observable.
    - Only acceptable use of `@` is on trivially safe operations where failure immediately checked (e.g. `@unlink()` followed by existence check).

#### Laravel

1. **Async/distributed command correctness** — for commands dispatched async (message-bus/queue):
    - Derive behaviour from **persisted state**, not a flag carried on a single queued message (a lost/retry-exhausted message silently loses the intent).
    - Make dispatch **idempotent**: a retried command must re-enqueue the lost side-effect when the persisted state says it is still pending.
    - Check-then-act races: an existence check is not atomic with a later insert — convert the resulting DB constraint failure into the intended domain exception (e.g. non-retryable conflict) instead of leaking a generic DB error that retries forever.
    - Cancellation paths must **clear persisted flags/states** — a cancelled operation must not leave a flag that permanently blocks the feature.
    - A retried command must **re-validate every dispatch-time precondition from persisted state**, not just one field. Distinguish **terminal no-op states** (cancelled, never eligible — return silently, a later re-dispatch is impossible or unnecessary) from **retryable not-ready states** (e.g. awaiting confirmation or dependency sync — throw so the bus retries). A retry that swallows a not-ready state as success permanently loses the intent.
    - Verify the **re-dispatch path exists** for every state that becomes ready without saving the aggregate that triggers the observer (e.g. confirmation or group-sync rows saved without a `Trip::save()`): if no later observer fires, the ride/job is permanently missed unless the command retries itself.
2. **Test coverage of security-critical and infrastructure code** — adapters, middleware, and security-critical branches need **direct tests**, not only handler-level tests with fakes; cover the happy path and every rejection path; verify security claims at runtime (e.g. a signature validated by the _secondary_ key when multi-cert support is claimed).
    - A test must exercise the **real middleware stack on the path under test** — `WithoutMiddleware` (or a fake auth guard) masks exactly the auth/preflight behaviour the change is about; add a middleware-enabled test for auth-gated routes (e.g. an OPTIONS preflight must be answered before auth rejects it).
    - A test that **passes via type coercion** (e.g. asserting a `string` where an `int` column stores `0`, MySQL coerces `'PHPUNIT_RIDE_ID'` to `0`) proves nothing — assert the real persisted value in its true type so the test fails if the value is never written.
3. **HTTP error/exception semantics** — a domain exception mapped to an HTTP status must carry that semantics itself and behave consistently across every response path:
    - Extend `HttpException` with the status (e.g. 409) so any path that falls through to the default renderer still returns 4xx instead of 500 — do not rely only on named handlers matching the exception.
    - Bound status-range checks to **400–499**: a `< 500` check accepts 1xx/2xx/3xx and renders a non-error page for e.g. a 302 without its `Location` header.
    - Preserve `HttpException` headers (`Allow` on 405, `WWW-Authenticate` on 401, `Retry-After` on 429) on the rendered response.
    - Only render **vetted messages** (the explicit domain exception) to signed-out users; arbitrary 4xx messages may carry internal context.
    - Apply the same exception type across **all sibling code paths** (e.g. `updateCost` and `updateSales` both throw `InvoicePeriodClosedException`), not just the path under test.
4. **Catch-all fallback & HTTP-method semantics** — when a catch-all/fallback route is added or changed:
    - Preserve real-route **405 + `Allow`** for paths registered under another verb; map only truly-unknown paths to 404. A catch-all matching every verb turns legitimate method mismatches into 404s.
    - Derive the `Allow` header from **non-fallback routes only**; if the catch-all matches every verb, an OPTIONS probe advertises methods that do not exist.
    - Answer OPTIONS **before auth middleware** for authenticated groups: register a dedicated pre-auth OPTIONS route (a fallback inside an auth group makes preflight return 401). Keep every fallback's OPTIONS branch reachable — excluding OPTIONS from a shared helper silently disables the controllers' OPTIONS handling.
    - Route registration order decides precedence for same-URI patterns; verify with a middleware-enabled test, not just a `WithoutMiddleware` one.
5. **View/layout rendering** — a view rendered as a response must extend a layout: a Blade file containing only `@section` blocks produces an **empty body** when used as the top-level view. Wrap it in the layout's `viewContent`/`contentView` slots, and add a test asserting the rendered body contains the intended content.
6. **Laravel Authorization & Policies** — when a Laravel controller's `authorize()` calls or policy methods are added or modified:
    - Verify controller `authorize()` calls pass VOs to policies, not raw primitives, when VO already constructed in controller.
    - Verify policy methods accept corresponding VO type, not primitive.

#### Kubernetes

1. **Kubernetes Manifest Consistency** — when changeset includes Kubernetes YAML manifests (any file with `apiVersion` and `kind`):
    - When multiple resources share same `apiVersion`/`kind`, verify they have consistent ArgoCD annotations (`sync-wave`, `sync-options`). Inconsistent annotations across resources of same kind is WARNING.
    - When resource uses Custom Resource `apiVersion` (not core `v1`, `apps/v1`, `batch/v1`, `networking.k8s.io/v1`, etc.), verify it has `argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true` if CRD installed by another Application in same changeset. Missing this annotation causes ArgoCD dry-run failures on first sync — flag as WARNING.
    - When `kustomization.yaml` exists in same directory as new resource file, verify new file listed in `resources:`. Unlisted resource in Kustomize-managed directory will not be synced — flag as BLOCKER.

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
> - **Test Quality** — Descriptive names? Comprehensive coverage? Reusable named test doubles? Assertions match method name claims (ordering, cardinality, conditions)? No coverage regression (assertions not removed or narrowed without updating test name)? No orphaned fixture files? No redundant traits/mixins already provided by the base test class?
> - **Decorator & Wrapper Integrity** — All parameters forwarded through decorators? De-facto convention params forwarded?
> - **State-Machine Reset Placement** — Resets on correct branch? Every path that should seed accumulator does so?
> - **Utility Method Abstraction Bypass** — Sibling method state machine not driven into inconsistent state?
> - **N+1 Query Regression** — Bulk-loads not undermined by remaining per-row lazy loads in same pipeline (including in called helper methods)?
> - **Primitive Obsession** — Commands, queries, and controllers use VOs when domain VO exists?
> - **Hardcoded Configuration** — No hardcoded URLs, hostnames, or environment-dependent values in application/domain handlers?
> - **Magic Values** — Domain-meaningful literals extracted to class constants?
> - **Log Level Appropriateness** — Hot-path log statements use `debug` for routine "nothing happened" messages?
> - **Return-Type Contraction Safety** — Proposed type narrowings survive every runtime branch (pass-through/fallback paths) and existing callers/tests?
> - **Recurring Issue Types (Generic)** — TOCTOU/concurrent modification? Config-like entity invariants? Migration `down()` restores exact schema? API contract round-trip? Docs match implementation (incl. docblocks)? Architecture/design smells? Atomic commit structure? Configuration & rollout? Per-request performance? Deployment/queue rollout compatibility?
> - **Recurring Issue Types (Technology-specific)** — For each technology in use: PHP (SSRF/untrusted remote input, baselines not grown, `@phpstan-ignore` masking real type mismatches, extension guards cover all required extensions, global state restored in `finally`, `tearDown()` wrapped in nested `try/finally`, PSR-3 logs include `'exception' => $e`, no `@` operator), Laravel (async command correctness, real middleware stack on tested path, HTTP error/exception semantics, catch-all fallback & HTTP-method semantics, view/layout rendering, `authorize()`/policies use VOs), Kubernetes (manifest consistency, `SkipDryRunOnMissingResource`, `kustomization.yaml` resources)?
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
