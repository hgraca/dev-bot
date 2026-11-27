
41. **A layered source must not resurrect what the authoritative one rejected** — when two or more sources (config files, manifests, overlays) fill one resolved map and one of them is the authority per entry:
    - Confirm a lower-precedence source cannot supply a value for an entry the authoritative one **rejected** — a parse error or an unreadable flag drops the entry from the resolved map, and a "fill in the gaps" pass (`setdefault`, `??`, `merge` with the secondary as the target) then reports the entry as valid while the error list says otherwise.
    - Require the negative case in the tests: authoritative entry malformed **and** a duplicate in the secondary source, asserting the resolved state still reports the error.
    - WARNING; BLOCKER when the resolved answer is `enabled`/`valid` and something acts on it while the error list contradicts it.

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
9. **Assumed third-party security defaults** — when a change relies on a security property of a third-party library (signature requirements, validation guarantees, atomic single-use operations):
   - Verify the library's actual defaults in the installed vendor code and flag properties that are **assumed but not explicitly set**. Example: onelogin/php-saml `strict => true` does NOT imply `wantAssertionsSigned` (defaults false) — a signed response carrying an unsigned assertion is accepted unless the setting is explicit.
   - The same principle applies to any security-relevant library knob the change depends on: check the default, set it explicitly, and say so.
10. **Credentials hashed before persistence** — for every path that writes a password or credential (provisioning services, factories, seeders, imports):
    - Verify the value is hashed (`Hash::make`, bcrypt, etc.) before storage. A generated credential (`Str::random(...)`) passed raw to a model constructor or repository is stored as plaintext — flag as BLOCKER even when the password is unusable (e.g. SAML-provisioned users excluded from password login).

#### Laravel

1. **Async/distributed command correctness** — for commands dispatched async (message-bus/queue):
   - Derive behaviour from **persisted state**, not a flag carried on a single queued message (a lost/retry-exhausted message silently loses the intent).
   - Make dispatch **idempotent**: a retried command must re-enqueue the lost side-effect when the persisted state says it is still pending.
   - Check-then-act races: an existence check is not atomic with a later insert — convert the resulting DB constraint failure into the intended domain exception (e.g. non-retryable conflict) instead of leaking a generic DB error that retries forever.
   - Cancellation paths must **clear persisted flags/states** — a cancelled operation must not leave a flag that permanently blocks the feature.
   - A retried command must **re-validate every dispatch-time precondition from persisted state**, not just one field. Distinguish **terminal no-op states** (cancelled, never eligible — return silently, a later re-dispatch is impossible or unnecessary) from **retryable not-ready states** (e.g. awaiting confirmation or dependency sync — throw so the bus retries). A retry that swallows a not-ready state as success permanently loses the intent.
   - Verify the **re-dispatch path exists** for every state that becomes ready without saving the aggregate that triggers the observer (e.g. confirmation or group-sync rows saved without a `Trip::save()`): if no later observer fires, the ride/job is permanently missed unless the command retries itself.
   - Do not judge atomicity on an assumed transaction boundary: establish from configuration that a transaction wrapper sits in a middleware list that actually runs for this message (dispatch-time lists carry logging and context, never the wrapper), and establish how this project **composes** those lists — a configured list may replace the defaults or merge with them, so read the semantics rather than assuming replacement. The generic rule is in `devbot:software-development` → `annexes/system-design/message-bus.md`; the `get-e/message-bus` keys (`command_bus.sync_middlewares`, `command_bus.async_middlewares.execution_middlewares`, `event_bus.execution_middlewares`, `transaction.max_nested_transactions`) are in `annexes/php/message-bus.md`.
2. **Test coverage of security-critical and infrastructure code** — adapters, middleware, and security-critical branches need **direct tests**, not only handler-level tests with fakes; cover the happy path and every rejection path; verify security claims at runtime (e.g. a signature validated by the _secondary_ key when multi-cert support is claimed).
   - A test must exercise the **real middleware stack on the path under test** — `WithoutMiddleware` (or a fake auth guard) masks exactly the auth/preflight behaviour the change is about; add a middleware-enabled test for auth-gated routes (e.g. an OPTIONS preflight must be answered before auth rejects it).
   - A test that needs a **specific host** must build the request itself: the feature-test client derives scheme and host from the app root, so an `HTTP_HOST` server var never reaches `$request->getHost()`. Construct it with `Request::create('https://host/path', 'OPTIONS', server: [...])` and invoke the unit under test directly; a test whose two sides both resolve `localhost` proves nothing about host-dependent behaviour.
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
7. **API resource serialization is scalar** — for every field in a resource `toArray()` or a JSON response array:
   - Verify the value is scalar (string/int/bool/array). Backed enums must use `->value`; value objects must use `->getValue()` (or an explicit string conversion). Never rely on implicit `JsonSerializable`.
   - json_encode of a PHP backed enum (no `JsonSerializable`, no public properties) silently yields `{}` — clients receive `"status": {}` with no error. A VO that implements `JsonSerializable` works but relies on the interface staying present.
   - Response tests must assert the serialized field value (`assertJsonPath('data.status', 'active')`), not just presence — the bug only surfaces when a test reads the field.
8. **Validation bounded to DB schema** — for every string field validated by a FormRequest:
   - Verify a `max` rule matches its DB column length (`string(255)` column → `max:255`); oversized input must fail validation (4xx) before reaching the DB (500).
   - Check list-item rules too (`email_domains.*`), not just scalar top-level strings. A unique-index column (`string(255)`) exceeded by input is the common 500 leak.
9. **DB constraint-violation → field mapping** — when a handler converts a unique-key `QueryException` (MySQL 1062) into a 4xx validation error:
   - Verify the mapped field matches the actually-violated constraint, not a hardcoded field. Parse the key name from the error message (`for key 'schema.table_index'`) and map it (e.g. `*_slug_unique` → `slug`, `*_owner_key_unique` → `owner_type`); fall back to a default only for unknown keys.
   - A 400 that blames the wrong field (always `email_domains` when `slug`/`owner_key`/`idp_entity_id` was violated) misleads clients and makes conflicts unresolvable.
10. **Case-sensitive identifiers need binary collation** — when a migration creates a column that stores identifiers matched server-side (SAML entity IDs, codes, tokens):
    - Verify the column uses a case-sensitive (binary) collation, e.g. `->collation('utf8mb4_bin')`. The default `utf8mb4_unicode_ci` is case-insensitive: a UNIQUE index and lookups (`WHERE col = ?`) conflate values differing only by case.
11. **Single-use cache consumption must be atomic** — when a one-time token/correlation value is consumed from the cache:
    - Verify the consume is atomic. `Cache::pull()` is read-then-delete (get + forget): two concurrent requests can both read the same value before either delete lands, breaking single-use guarantees. Guard with a cache lock (`Cache::lock(...)->get()` + `finally` release) or an atomic GETDEL.
12. **Route params constrained to value-object constructors** — when a route parameter feeds a value-object/entity constructor (`new SomeUuid($routeParam)`):
    - Verify the route constrains the parameter (`->whereUuid('uuid')`, etc.) so malformed input is a 404, not a constructor exception (e.g. `InvalidUuidException` → 500).
13. **A hand-written matcher reproduces the framework's own matching rules** — when the change re-implements a check Laravel already performs (matching a path against a config list, comparing origins, resolving a route):
    - Verify it accepts **every shape the config key accepts**. A path list may be flat, or keyed by host with each host carrying its own list (`['portal.example.com' => ['api/*']]`); a matcher that reads only the top-level list silently drops every keyed entry, so those paths exist in configuration and never match.
    - Verify the **edge values**: `'/'` is the root path itself, not an empty prefix — trimming slashes from every entry turns it into `''`, which then matches everything or nothing depending on the matcher. Read the framework's implementation (`Illuminate\Routing\Route::hasMatchingPath`, `CorsService::isOriginAllowed`) and copy its normalisation instead of inventing one.
    - Require a test per shape the key can take — flat list, host-keyed, root path — because the flat-list test passes while the other two are dead.
    - WARNING; BLOCKER when the dropped shape or value is the one the deployment actually configures.

#### Kubernetes

1. **Kubernetes Manifest Consistency** — when changeset includes Kubernetes YAML manifests (any file with `apiVersion` and `kind`):
   - When multiple resources share same `apiVersion`/`kind`, verify they have consistent ArgoCD annotations (`sync-wave`, `sync-options`). Inconsistent annotations across resources of same kind is WARNING.
   - When resource uses Custom Resource `apiVersion` (not core `v1`, `apps/v1`, `batch/v1`, `networking.k8s.io/v1`, etc.), verify it has `argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true` if CRD installed by another Application in same changeset. Missing this annotation causes ArgoCD dry-run failures on first sync — flag as WARNING.
   - When `kustomization.yaml` exists in same directory as new resource file, verify new file listed in `resources:`. Unlisted resource in Kustomize-managed directory will not be synced — flag as BLOCKER.

2. **Relocating a manifest** — when the change moves or renames a manifest, or the directory that holds it:
   - Verify every other declaration of the same object is removed in the same change. Two files declaring one object give it two owners: whichever applies last wins, and the other reports drift forever. BLOCKER.
   - Verify load-bearing metadata survives the move — `argocd.argoproj.io/*` annotations, tracking labels, and any selector a controller matches on. A relocated object that lost its `sync-wave` is not the same object. WARNING.
   - Verify the controller that rendered the old location can no longer prune it. A directory that still renders something compares the rest of its set and deletes what disappeared; only a path that no longer exists stops the comparison. Moving the last file out of a directory and moving one of several are different changes. BLOCKER when the pruned object owns resources of its own.
   - Verify the new location matches the glob the generator actually reads — name, depth and the segment that decides the namespace or destination. A directory the generator does not match is applied by nothing.

3. **A shared generator template is blast-radius-wide** — when the change edits an ApplicationSet, Helmfile, or any generator whose template serves many generated units:
   - A field that selects the source _type_ applies to every unit, not only the one the change targets: adding a directory-mode block to a template that also generates kustomize units switches them all, dropping their patches and generated names. BLOCKER.
   - A template that reads a per-unit key must fail closed for all of them, so verify every input carries it — one missing key stops the whole generator, not the incomplete unit. BLOCKER when the generator is what creates the objects.
   - Verify per-unit options the hand-managed predecessors carried are expressed by the template. Adoption rewrites the generated unit's whole spec, so an option the template omits is silently lost on the next reconcile. BLOCKER when the option governs how a destructive apply behaves.

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
> - **Registration Completeness** — Would the suite stay green if the artifact were never wired up?
> - **Hand-Maintained Coverage Lists** — Does a test iterate a literal set the change is missing from?
> - **Claims About Existing Mechanisms** — Is every factual sentence about existing behaviour verified, not merely plausible?
> - **Unverifiable Claims** — Deleted rather than hedged?
> - **Exit-Status Semantics** — Every code's meaning stated, including the ones that mean "no answer"?
> - **Working-Directory Scope** — Every call scoped to the resolved target, not to the process cwd?
> - **Procedure Described as Enforcement** — Is a document's instruction kept distinct from a platform guarantee?
> - **Second-Order Damage While Fixing** — Would each applied fix survive re-reading against its own finding?
> - **Recurring Issue Types (Generic)** — TOCTOU/concurrent modification? Config-like entity invariants? Migration `down()` restores exact schema? API contract round-trip? Docs match implementation (incl. docblocks)? Docs/runbooks issue only scoped, reversible commands? Architecture/design smells? Atomic commit structure? Configuration & rollout? Per-request performance? Deployment/queue rollout compatibility? Concurrent-race recovery guards the actual failing operation (`new()` vs `save()`)? Bootstrap path for newly-gated admin capabilities? Cached build artifacts renamed or invalidated when their inputs change? Request parameters validated rather than coerced? Blanket filters not defeating an always/never guarantee? Reused checkouts validated before writing? Generated refs unique under concurrency? Symlinked paths resolved before check/copy/stage? Credential graded by every surface (argv, environment, file and directory mode, logs, inspection output) with permissions enforced rather than attempted? A hazard documented once applied everywhere it occurs?
> - **Recurring Issue Types (Technology-specific)** — For each technology in use: PHP (SSRF/untrusted remote input, baselines not grown, `@phpstan-ignore` masking real type mismatches, extension guards cover all required extensions, global state restored in `finally`, `tearDown()` wrapped in nested `try/finally`, PSR-3 logs include `'exception' => $e`, no `@` operator, assumed third-party security defaults, credentials hashed before persistence), Laravel (async command correctness, real middleware stack on tested path, HTTP error/exception semantics, catch-all fallback & HTTP-method semantics, view/layout rendering, `authorize()`/policies use VOs, API resource serialization is scalar, validation bounded to DB column lengths, DB duplicate-key handlers name the violated field, case-sensitive identifiers use binary collation, single-use cache consumption atomic, route params constrained to VO constructors), Kubernetes (manifest consistency, `SkipDryRunOnMissingResource`, `kustomization.yaml` resources)?
> - **Code Style** — Symbols imported? No FQCNs inline? Explicit guards? Sealed/final convention?
> - **Role Compliance** — All code changes made by the developer?
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
