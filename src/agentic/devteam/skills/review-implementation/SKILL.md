---
name: devbot:review-implementation
description: "Use when reviewing a code changeset against a plan before it merges."
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
- When a test pins documented behaviour by matching prose (a `grep` over a skill or doc file), require the property in **one** matcher: two independent greps each pass while the sentence between them is gone, so the promise in the test name — order, gating, adjacency — silently stops being asserted. WARNING.
- **Prove the new check can fail** — break the input it guards deliberately (delete the block, reword one bullet, remove the anchor) and confirm the test reports it. A test whose failing case has never been exercised is a claim, not a check. Three shapes pass while asserting nothing, and all three look correct when read: a scan whose path or glob resolves wrong, so its loop runs zero times; a matcher loose enough to accept a different input (a heading found anywhere above, rather than the one adjacent to what it labels); and a comparison that relates only the copies to each other, which a synchronized rewrite in all of them satisfies. Require a mutation check for each new guard, and a scan that asserts what it scanned — an **exact** count, never a floor, because a floor also passes when the reader starts and then dies part-way. WARNING; BLOCKER when the test is the only evidence for a behaviour change.

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

### 16. Registration Completeness

When the change adds an artifact (skill, command, agent, hook, tool, migration, config file):

- Verify something asserts the system will **see** it — linked, registered, loaded, discovered — not only that the file exists and its content is correct. A test over the source file plus its manifest is not a registration test.
- Ask directly: if this artifact were never wired up, would the suite stay green? If yes, WARNING.

### 17. Hand-Maintained Coverage Lists

When a test iterates a hard-coded set — module names, file names, case tables:

- Verify the change appears in that set. If it does not, the assertion never ran and the artifact is unverified while the suite is green.
- Flag the pattern itself: a literal list that must be edited with every addition is a latent blind spot. Prefer one derived from the tree — WARNING on the pattern, not only on the omission.

### 18. Claims About Existing Mechanisms

When the diff states a fact about how an existing mechanism behaves — "it prunes", "every module does X", "the range is 10–40":

- Verify each claim against the source, or by running it. A plausible sentence in a document is a factual assertion, and unverified it becomes the next reader's wrong belief.
- A count, a range, or a "every/all" quantifier is the highest-risk form: it is cheap to check and easy to get wrong.
- A **negative or complete** claim — "only these routes are public", "nothing else reads it" — needs the full set enumerated (the route table, the registry, every call site), not a spot-check. A refutation that holds only while a dependency is healthy names that condition instead of closing the finding.
- An unverified claim about existing behaviour is WARNING; one that a reader would act on is BLOCKER.

### 19. Unverifiable Claims

When a claim cannot be established from the repository at all:

- The finding is the claim itself. Recommend deleting it rather than hedging it — a softened unverifiable claim still misleads.
- WARNING; BLOCKER when a reader would make a decision on it.

### 20. Exit-Status Semantics

When the diff reads a command's status to decide something:

- Enumerate the meaning of every code it can return, including the ones that mean "no answer" and "not applicable here".
- Check that no code is silently mapped to success or failure. An inverted mapping is BLOCKER when the decision it drives is destructive or irreversible.
- When a command is used as a **probe** — "is this present?", "does it exist?" — verify what it does in the absent case. Many resolvers exit `FATAL` rather than printing nothing, so "empty output means absent" inverts on the ordinary first run; require the list/query form that reports absence instead. WARNING.

### 21. Working-Directory Scope

When a command inspects or acts on a target the text has just resolved:

- Verify every call is scoped to that target — a `-C`/`--directory` equivalent, or an explicit path — not to wherever the process happens to run.
- An unscoped call answers about a different thing and usually still exits 0, so the failure is silent.
- A **repository** is a target too: `gh`, `git`, and tools taking `--project`/`--repo` resolve it from the working directory when no flag names one, so a procedure that runs from one repository and acts on another answers about the wrong one.
- A default directory written as a literal (`./.agents/…`) is the same defect where the project configures it — require the configured value, not the convention.
- WARNING; BLOCKER when what it acts on is production or irreversible.

### 22. Procedure Described as Enforcement

When the text describes a control — a gate, a check, a guard:

- Distinguish what a document instructs from what the platform guarantees. A procedural control described as enforced is worse than one described honestly, because the reader stops checking.
- An executable block **is** the procedure, not an illustration of it: when the prose promises a step — a plan preview, a verification, a confirmation — the block must contain it, and every step the block runs must be one the prose describes. Read the whole block, not the sentence that cites it.
- WARNING.

### 23. Second-Order Damage While Fixing

When the change is itself a fix, or when a later round of the same review answers earlier findings:

- Re-read the whole section around each edit, not just the edited sentence: an anchor can be dropped, a hazard the same file warns about can be reintroduced a few lines later, and counts go stale.
- Re-verify each applied fix against its own finding before closing it — a replacement that silently matched nothing looks exactly like a successful edit.
- Re-read the file's prohibitions, not only its requirements: a rule the change adds can contradict a MUST NOT a few lines away — each half correct alone, impossible together.
- WARNING; BLOCKER when the earlier round already reported the finding resolved.

### 24. Decision Tables and Retry Paths Cover Every Reachable State

When the change documents a choice — a table, an if/else procedure, a resume or retry step:

- List the states the document itself names, then check each has a row or a branch: present/absent, local/remote only, open/merged/closed, first run/rerun, declined/abandoned. A state named elsewhere in the same section but missing from the table is a finding.
- Check no unconditional step follows the table: "reuse the existing branch" in the table plus "create the branch" below it fails on the very case the table handles.
- Check the first run is a row, not an error path — the ordinary case must be the one the procedure was written for.
- WARNING; BLOCKER when the missing state makes the documented procedure fail or act on the wrong target.

### 25. A Conditional Gate Defines Its Term

When a step or check is gated on a word — "a review loop ran", "the work is landed", "finished":

- Require the term defined where the condition is introduced, and its lookalike excluded by name. The same session usually has a near-miss the reader will substitute: our own pre-pull-request review pass is not a pull-request review loop.
- Check every restatement of the gate uses the defined term; a paraphrase in a sibling file reads as a second, looser gate.
- WARNING; BLOCKER when the looser reading makes the step run where it cannot work.

### 26. A Staged Change Is Safe in Every Intermediate State

When the change lands in more than one step — a migration between systems, a mode switch on a running deployment, a rename spread across releases, or a step an operator runs by hand:

- Enumerate the states the system passes through, not only the final one, and require each to be correct rather than merely reachable. A reference that becomes meaningful only after a later step is a live fault until that step runs.
- Assume the steps run out of order, or that one is never taken. The single ordering that works is not the one to verify.
- Scrutinise every intermediate state where a name is unqualified, a default applies, or a value is resolved by fallback: a bare name resolves to wherever the fallback points, which is rarely the intended target.
- When the rollout depends on a manual step, the change must be safe if that step is skipped entirely.
- BLOCKER when an intermediate state would serve the wrong artefact or take the deployment down.

### 27. A Fixed Value Is Fixed Everywhere It Is Repeated

When the change corrects a literal — a version, an image tag, an extension pin, a port, a timeout, a mode flag — that is also carried by sibling configuration:

- Search every file type for the old literal and list the occurrences before calling the fix complete: workflows, Dockerfiles, compose files, env files, scripts and docs.
- Fix each occurrence, or state explicitly why one is deliberately left. A sibling still carrying the old value is the same defect, unfixed.
- Never assume a second file inherits the first: files that look parallel usually hold their own copy.
- WARNING; BLOCKER when the un-updated copy runs in CI or production.

### 28. A Composed Skill's Terminal Phase Runs Exactly Once

When a change composes skills, commands or procedures that each end in a terminal phase — squash, hand-over, publish, merge:

- List every unit the composition invokes and name its terminal phase. Then show where that phase runs in the composition, and confirm it runs **once**. A command that says "run the loop" and then adds its own squash step invokes the loop's finish **and** performs one, so the history is rewritten twice and the operator approves it twice.
- A composition that needs a unit's cycle but not its finish must bound the invocation explicitly ("drive its loop and gate, then stop before its finish"), or own the finish and say so. An unbounded "run X" hands the terminal phase to X silently.
- Check the read-only sibling too: a unit whose finish publishes must not be invoked for a step that only inspects.
- WARNING; BLOCKER when the duplicate terminal phase rewrites published history or repeats an irreversible action.

### 29. A Pointer to an Owner Resolves

When text assigns a behaviour to another document — "the loop owns the push", "the adapter carries the wait", "the workflow squashes the fixups":

- Open the named document and verify the behaviour is **defined there**, as a step or a stated rule, not merely named. A pointer to a rule that does not exist leaves the behaviour unowned: every reader follows the pointer and finds nothing, and nothing in the file that assigns it ever performs it.
- Check the pointer's direction when the behaviour moves: the new home names it, and the old home no longer claims it. Two documents each saying the other owns it is the same defect with both ends missing.
- The failure is silent when the unowned action is one of a sequence — the push, the re-request, the gate — because the procedure still reads as complete.
- WARNING; BLOCKER when the procedure cannot work at all without the unowned action.

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
   - When the change alters **when a setting is honoured**, the prose describing that setting is part of the change: a sentence that stays true of the library yet false of the configuration it sits in — an empty list still allows every caller, while the new gate makes the list mandatory — misleads the next operator even though no clause in it is factually wrong.
   - An **amendment banner is not an amendment**: when a note or doc supersedes an earlier instruction, mark the retired instruction in the paragraph it governs — or remove it. A banner above a paragraph that still tells the reader to do the old thing is a finding; the reader follows the paragraph, not the banner.
6. **Architecture/design smells** — ports named by domain/area (not by implementation); API inputs reduced to what cannot be derived; no duplicated output or duplicated invariants (single source of truth); queries/logic in intent-named private methods; **compare values before mutating** them; check mutation order (comparing post-mutation values is always equal).
7. **Atomic commit structure** — one logical change per commit; migration-only commits; related cleanup grouped with its change; unrelated changes not bundled.
8. **Configuration & rollout** — only non-default config values should be specified (do not replicate package defaults); env switches/flags must be safe for fresh environments (provisioning must be part of the rollout, or the switch stays off).
9. **Per-request performance** — request-path code must not do work proportional to a global structure per request:
   - Do not scan the full route collection (hundreds of routes × regex) per fallback/404 request — use the framework's compiled matcher.
   - Keep synchronous waits (e.g. Kafka `flush()`, external calls) short for request-path observers/loops; a 10s per-call stall on outage exhausts workers. Long delivery/retry windows belong in a background/outbox path, and the config comment must state which is which.
10. **Deployment/queue rollout compatibility** — deleting a queued job class breaks payloads already waiting/retrying in the queue (they must unserialize the old FQCN): keep a **compatibility shim** class delegating to the new implementation until the queue retention window elapses (note the removal date in the class), or document an explicit drain/migration rollout.
11. **Concurrent-race recovery guards the actual failing operation** — when code catches a DB constraint violation (e.g. MySQL 1062 unique-key) to recover a concurrent race (re-fetch instead of failing):
    - Verify the guarded call is where the exception is actually thrown. In Eloquent, `Model::new()` builds an **unsaved** model — the insert happens at `save()`, so a try/catch around a repository `create()` only works if that method persists before returning. A recovery wrapped around a non-persisting "create" is dead code: the losing request still surfaces an uncaught `QueryException`.
    - Check the recovery path: after catching the violation, re-fetch the row and continue idempotently (both racing requests succeed), or map to the intended domain exception.
12. **Bootstrap path for newly-gated admin capabilities** — when a new privilege flag/role (defaulting to false) gates an admin or CRUD capability:
    - Verify an operator bootstrap path exists (CLI command, seed/backfill of known accounts, or documented deployment step). A flag that ships false for every existing user and gates the only API that can create initial state (e.g. the first SAML config) locks out the first admin.
    - Do not rely on a migration backfill unless it can name the trusted accounts; an explicit CLI command is the safe default.
13. **Declared interface vs the consumer's parser** — when the change adds a schema, manifest, tool descriptor or protocol message that another component reads:
    - Read the consumer's parser and verify it can express **everything the declaration advertises**. A property the consumer drops, or a shape it reads as empty, is the finding even though each side looks correct alone — the feature works from one entry point and silently fails from the other.
    - A declaration is not a contract until something enforces it: check that a test or validator fails when the two drift, because this class of mismatch passes every happy-path test.
    - WARNING; BLOCKER when the dropped value makes the feature unusable through its advertised interface.
14. **External list and event reads: paginate, filter, bound by revision** — when the change reads a remote list, timeline or event log to decide something:
    - **Paginate**, and filter to the subject (the bot, user or type meant) rather than taking the last entry — a mixed, multi-page response lets an unrelated entry end the logic or hides the one that matters.
    - **Bound by the current revision**: an append-only history keeps old answers forever, so "an entry exists" is not "the current state is answered". Compare against the current head/version, or track a cursor taken before the action.
    - Distinguish "the call failed" from "the answer was empty": a failure mapped to empty looks like a settled result and turns into a timeout or a silent skip.
    - WARNING; BLOCKER when the read drives an irreversible action or a gate.
15. **A hand-written guard enforces the whole contract, not one token of it** — when the change validates an identifier, name or path segment itself (rather than through a framework validator):
    - Derive the contract from what the code does with the value — a filename, a namespace key, a URL segment, a user-visible id — then check the guard against every form that contract forbids: empty, whitespace, the separator alone, a trailing delimiter. A prefix or presence test that admits an empty remainder (`foo:`, `foo: bar`) passes every happy path and ships a malformed identifier into the place the guard was added to protect.
    - Require a test per rejected form. A guard whose rejection cases are untested is a comment, and the malformed value only surfaces in the artifact.
    - WARNING; BLOCKER when the value reaches the filesystem, an external namespace, or a user-visible identifier.
16. **A persisted record is consulted as a value, not as its own metadata** — when the change reads a sidecar or record file another step wrote (a stored path, id, version or flag): verify the reader validates **what it read**. An execute-bit test aimed at the record file inspects the container, not the value it holds — a record written as a scalar path with ordinary permissions fails that test permanently and rejects the correct value, so read the contents and validate the resolved value instead. Metadata checks that constrain the record itself, such as size bounds or freshness, are legitimate; they still never stand in for validating the stored value. Check the other direction too: a producer writing an unstructured scalar while the consumer parses a structured document, or one that omits the trailing newline the consumer requires, is the same defect seen from the write side. WARNING; BLOCKER when the miss silently routes the caller to a fallback that changes behaviour — a reinstall, a re-resolve, or a degraded mode that hides the correct value.
17. **A test fixture reproduces the production artifact's real shape** — when a test builds the input a production path consumes (a record file, a config, a generated fixture, a captured payload): compare the fixture against the producer for the properties the code depends on — permissions, encoding, format, and the type each value carries — substituting stable test values for environment-specific ones such as temp paths, timestamps and versions. A fixture **more permissive than reality** — an execute bit set on a file the producer writes with ordinary permissions, a hand-built mapping where the runtime passes a model object — hides exactly the defect the test exists to catch, and keeps the suite green while the real path is broken. Ask what the test would do if the fixture carried production's shape and access semantics: when the answer is "fail", the fixture is the defect. Reserve literal-content equality for deterministic records. Check the fixture's **controls** as well as its content: a knob that cannot express a state the test names — an empty value a `${VAR:-default}` expansion silently turns into the default, a flag with two positions for a three-state input — makes the test a second copy of its neighbour, asserting a different case than the one its name claims while passing either way. Check the double's **declared type** as well as its values: a widened input type — `Partial<HostPayload>`, `any`, or a cast — erases requiredness the producer enforces, so the double can emit a shape reality never produces while every assertion still passes; tie the double and its emitter to the producer's own type. WARNING; BLOCKER when the test is the only evidence for a behaviour change.
18. **Documentation and runbooks issue only scoped, reversible commands** — when the change adds or edits documentation, a learning note, or a runbook containing shell commands:
    - **Destructive commands need a scope and a way back** — `migrate:fresh`, `DROP`, `rm -rf`, or `--force` against state the reader may not be able to recreate must say what it destroys and when it is safe: a disposable database, a backup, or a schema-preserving alternative. A command that is safe in a throwaway container is not safe when the same page hands it to a developer against a shared volume.
    - **Permission widening is a security change** — `chmod -R 777` and `a+rwx` on a host bind mount expose every file under it to every local user. Prefer restoring ownership to the configured UID/GID and keeping owner/group modes; check what the change exposes, not only that it unblocks the run.
    - WARNING; BLOCKER when the command destroys data the reader cannot recreate or widens access on a shared host path.
19. **A narrowed allowlist admits every host the configuration itself declares** — when the change restricts which origins, hosts, addresses or identifiers may reach something (CORS origins, an IP allowlist, an authentication pattern, a redirect list):
    - Enumerate every value the configuration declares legitimate — the URL another config key defaults to, the hosts the deployment manifests route, the addresses an environment template ships — and test the new rule against each one. A rule that drops one is a finding: the configuration now contradicts itself, and the dropped host fails closed in production while every test that builds its own value passes.
    - Ask the inverse question the tightening invites: after this change, can the product's own declared entry point still reach what it is meant to reach? A rule narrower than the product's own published URLs is not hardening, it is an outage carrying a security rationale.
    - WARNING; BLOCKER when the dropped host is the one the deployment tells clients to use.
20. **A cached build artifact is invalidated when its inputs change** — when the change alters what a cached artifact is built from (an image's Dockerfile, extension or runtime versions, a lockfile, a toolchain pin) and something reuses that artifact by name — a build step that skips when the tag exists, a compose file pinned to a tag, a cache key, a prebuilt binary path:
    - Verify the name or key changes with the inputs: a version in the tag, a content hash in the cache key, or an explicit rebuild step. A skip-if-exists guard keyed on a name the change leaves untouched keeps serving the old artifact to every environment that already built it.
    - Ask what an **existing** environment does after pulling the change, not only a fresh one: the stale artifact meets the new requirements (an exact extension pin, a new runtime version) and fails, while CI and fresh checkouts, which always build from scratch, stay green.
    - WARNING; BLOCKER when the stale artifact cannot satisfy a requirement the same change introduces.
21. **A request parameter is validated, not coerced** — when the change reads a scalar from request input (query string, form, header) and converts it to a typed value (an integer limit, a page size, a boolean flag, an enum):
    - Verify the conversion rejects malformed input instead of casting it. A cast accepts what validation would refuse: a leading-digit string becomes its prefix (`3abc` → 3), an array becomes 1, an empty string becomes 0. Framework input helpers often cast by default — read the helper's implementation in the installed version rather than trusting its name.
    - Check that every malformed, missing and out-of-range value lands on the documented fallback or a 4xx, and that a test covers at least one non-numeric and one array input, not only the absent and valid cases.
    - WARNING; BLOCKER when the coerced value bounds a query or a resource (a limit of 0 or an unbounded page size).
22. **A skip decision is a record of completed work, and only a success may write it** — when the change lets a later run skip work because an earlier run "already did it" (a start/up probe, a done marker, a cache of a side effect, a resume checkpoint):
    - Clear the record **before** the attempt begins, not only on a failure the code anticipates: an abort in the middle — a failed step, a trap, a crash — otherwise leaves the previous success standing, and the next run skips the work this one did not finish.
    - Treat a tolerated failure as a failure for the record. A delegated script that logs a warning and exits 0 did not complete its work, so the marker must not be written on its behalf.
    - Require the record to encode the **state** it vouches for, not just the fact that a run happened: the services or artifacts it claims are running, and any configuration-derived input the work's effect depends on. When one is gone or has changed, the marker is stale and the work must run again — #20 applied to a decision record instead of a build artifact.
    - Read the skip branch's scope against the full work it bypasses, including work delegated to another script: a condition that only observes one part of it (the compose services, the last marker) permits the skip while the rest never runs.
    - WARNING; BLOCKER when a stale record lets a required service, migration or reconciliation step be skipped.
23. **A side effect reachable from two recovery paths runs at most once** — when the change adds a fallback that performs the same effect an earlier step may already have performed (a heal after a reconcile, a retry after a repair, a second migration pass, a re-deploy):
    - Enumerate every path in the run that can perform the effect, **including the ones the change did not add**, and check the second cannot fire after the first has. Two branches that each rebuild, recreate or migrate the same target are a finding even when each is correct alone: the pair turns one intended action into two on shared infrastructure.
    - Require the run to **record that the effect was attempted** and consult that record, rather than re-deriving it from the state it just mutated. The state the first path changed is the input the second path misreads — the target the first path just recreated is briefly not yet running, which is precisely what the second path reads as "still broken".
    - Decide which branch owns the decision and gate the other on the record: the intended outcome is one action, one verification and a report, not two attempts at the same target.
    - WARNING; BLOCKER when the effect touches shared infrastructure or destroys work — a force-recreate, a deploy, a destructive migration, a data rewrite.
24. **A lookup that returns the first match is verified against a document holding several** — when the change adds a helper that locates a section, entry, row or span in a text or markup file, and a guard or check is then built on it:

- Ask how many matches the input can hold, and verify the helper's answer for each. Returning the **first** match reads as correct on a file with one occurrence and silently narrows every rule built on it: the guard validates the first section, leaves the rest unexamined, and reports green. A category that appears three times is two-thirds unguarded.
- Prove the helper discriminates before trusting the guard — one match, no match, several matches — and check that **every** match is reported, not only the first. A guard that passes all three is doing its job; one that answers the same regardless of input is not reading the input at all.
- Apply the same question to the parse boundary: a stop condition that never fires reads the remainder of the file, so a ten-line section reports seventy and clears any minimum-count threshold. Verify the extractor's count on a known section before relying on a guard that counts.
- WARNING; BLOCKER when the guard is the only evidence that the artifact is covered.

25. **A test releases every long-lived resource it starts** — when the change adds or modifies a test that starts a timer, a subscription, a watcher, a server or a background task:

- Require the test to call the disposer before it returns, inside a `finally`. A test that starts a resource and asserts on it without releasing it leaves that resource running into every later test in the same process, and a leaked interval or subscription can keep the run alive after the last assertion.
- Check that the production code **offers** a release path, and that the test uses the same one the runtime does. A test that cannot dispose is evidence the API has no cleanup, which is the real finding.
- A fixture that hands back a disposer and a test that ignores it is the commonest shape of this defect, and it survives review because the test passes and the suite stays green.
- WARNING; BLOCKER when the leaked work reaches shared state — spawning processes, writing files, mutating the fixture other tests read.

26. **Every writer of the same file or state honours the same guard** — when the change adds a guard to one path that writes a shared artifact (a config file, a link farm, a manifest, a lock):

- Enumerate every writer of that artifact and check each applies the same condition. A guard inside a helper while another path writes the same entry directly is a guard bypassed, and a test that exercises only the guarded path cannot see it.
- Check the order the writers run in. A reconciliation pass that runs before the guarded step will write entries the guard would have refused.
- Where a writer matches text — a key, a section header — verify the matcher against the spellings a user's file can legally contain, not only the one the generator emits. A narrow matcher that fails to recognise an existing entry appends a second one, and the parser keeps the last: the user's array is silently replaced.
- WARNING; BLOCKER when the unguarded writer overwrites or discards user data.

27. **A later blanket filter does not defeat an earlier always/never guarantee** — when the change states that one class of item is always (or never) handled, and a later step skips or stages items through a general filter:

- Verify the general filter cannot silently drop the guaranteed item. An "always published" rule followed by a blanket "skip anything ignored" check is two policies in one flow; the exception must be explicit, and a guaranteed item the filter rejects must be reported as an error, not skipped.
- Ask what a conservative filter — an ignore rule, an allowlist, a `check-ignore` probe — does to the guaranteed class, and test that case. A guarantee that holds only while the filter stays permissive is not a guarantee.
- WARNING; BLOCKER when the dropped item is the feature's headline behaviour or leaves user data unhandled.

28. **A reused checkout is validated, never borrowed on trust** — when a procedure reuses an existing worktree, clone or checkout another run may own (a standing-PR branch, a cached build directory, a shared temp tree):

- Require the reuse to prove the checkout is clean and at the fetched tip before writing into it; a dirty or diverged checkout carries another session's staged changes or commits into the new commit. When the proof fails, use a fresh detached worktree or report and stop.
- Check the failure mode the reuse creates: a reaped path git still registers, a branch checked out elsewhere, a worktree that cannot be removed. A fresh detached worktree avoids all three.
- WARNING; BLOCKER when the new commit can include another session's work or lose it.

29. **A generated ref or identifier is unique under concurrency** — when the change generates a branch name, temporary path, lock key or id from a timestamp:

- Verify the generator cannot collide between two runs in the same second. A second-resolution timestamp alone is not unique; add a session nonce (a PID or random suffix) or retry on collision.
- Check the collision path: the second run must fail loudly or retry, not silently take the first run's branch or overwrite its work.
- WARNING; BLOCKER when the collision loses or mixes another run's commits.

30. **A path is resolved before it is checked, copied or staged** — when ownership, ignore rules or repository identity differ across a symlink (a vault link into a shared store, a linked worktree, a bind-mounted directory):

- Verify the operation uses the resolved physical target, not the path the caller named. `check-ignore`, copy and `git add` must all see the same target-relative path; a symlink checked in one repository and staged in another either fails as ignored or lands in the wrong tree.
- Ask which repository owns the resolved path and which repository the command runs against, and test the path through the link. Resolving late — after the check but before the copy — is the same defect.
- WARNING; BLOCKER when the miss silently drops the item or commits it to the wrong repository.

31. **A step declared non-fatal stays off the command that creates what it needs** — when text or code declares that a later step's failure costs only that step (an assignee, a label, a reviewer request, a notification applied once the object exists):
    - Enumerate **every documented form** of the sequence, including the raw fallback written for when a helper tool or wrapper is unavailable, and check the later step's flag appears on none of the earlier commands. A helper that assigns after creating while its documented fallback passes `--assignee` to the create command states a guarantee only one of the two paths honours, and the fallback is exactly the path a reader takes when the helper is missing.
    - Verify the guarantee against the platform's own ordering, never the flag's name: a client may apply post-create mutations after creation on the hosted product and resolve them before it on an enterprise edition, where the same flag aborts the creation. Name the host the guarantee holds for, or keep the step off the create command entirely.
    - Require the guard to pin the split rather than the whole section: the invocation carries the flag, and the create command carries none. An assertion that only looks for the flag anywhere in the section is satisfied by the fallback.
    - WARNING; BLOCKER when the documented path can destroy the object the sequence exists to create.

32. **A guard's scope equals the operation's scope** — when a step proves a property before acting on a range, a set or a collection (a rewrite range, a batch, an inventory), and the action then touches every element of it:
    - Compare the proof's subject against the action's subject **element by element**. Proving the named target safe while the action replays the whole range leaves every other element unproven — and the named target is the one a reviewer checks.
    - Re-prove against the state the action reads, immediately before the action runs. Elements added between proof and action — commits, entries, files — sit outside the proof, and a proof taken before a fetch describes the ref as it was, not as it is.
    - Require the proof to fail closed. A proof whose own failure reads as "nothing found" — a filter's non-zero status taken as no-match, an enumeration that errored — reports a clean result it never computed.
    - WARNING; BLOCKER when the action rewrites history, deletes, or is otherwise not recoverable from its own result.

33. **A documented command runs under the shell mode it will run in** — when the change ships a shell recipe in a document, runbook or skill:
    - Read the block as a script under `set -euo pipefail`, the mode these procedures declare. Every step must survive a stage that legitimately exits non-zero **and** still fail when a stage fails unexpectedly: `cmd | filter || true` swallows the upstream failure as readily as the filter's no-match, so guard the command whose status is expected, not the pipeline.
    - A step that must fail — a dry run whose editor aborts, a probe signalling "nothing there" by exiting non-zero — needs its status allowed explicitly **and** its intended effect verified (expected output present, target unchanged). A tolerated non-zero alone cannot distinguish the intended abort from a failure that happened before the step's own work.
    - Run the block once before approving it. Prose reliably describes recipes that cannot execute, and the block is the artefact that runs.
    - WARNING; BLOCKER when the recipe performs an irreversible or history-rewriting action.

34. **A step declared inert is inert in both directions** — when the change adds a probe, a healthcheck, a readiness check, or any step the text calls read-only, silent, or side-effect free:
    - **It must retain nothing server-side.** A probe that opens a stateful session, a connection, a lock or a temporary resource must close it on every exit path — including the success path, which is the one nobody notices. A probe running on an interval multiplies the leak by the container's lifetime, and the resource count only shows up as memory growth long after.
    - **It must write nothing it inspects.** Resolve, read and compare only: a probe that persists a value (a cache, a stamp, a config key) mutates the state it exists to describe, and a caller that trusts the probe now sees its own side effect as fact. Check the probe's whole call graph, not just its own body — every helper it invokes is part of the claim.
    - **A probe's failure must not be indistinguishable from its success.** An exit status the caller ignores, or a swallowed error that reads as "nothing there", converts a broken probe into a clean result.
    - WARNING; BLOCKER when the probe runs unattended on a schedule, or when its side effect changes what a later decision reads.

35. **A validated path is canonicalised before it is validated** — when the change accepts a filesystem path (a mount root, a workspace, an output directory) and enforces a boundary on it:
    - Normalise **first**, then apply every rule to the normalised value, and iterate the normalisation to a fixed point: one pass leaves `//`, `//foo/`, a trailing separator after stripping, and `.`/`..` segments intact, and a check satisfied by the raw form passes a value the boundary was meant to reject.
    - Refuse the filesystem root explicitly. A rule written only as "must be absolute and non-empty" accepts `/` — and `/` is the one value that turns a scoped mount into the whole host.
    - Require a test per rejected form, including the canonicalised aliases of a rejected value; a guard proven only against its literal example is a comment.
    - WARNING; BLOCKER when the value reaches a bind mount, a delete, or a path the process writes through.

36. **A configuration fixed at creation is reconciled, in full** — when the change adds or edits a resource whose configuration is applied once and then left alone (a container, a schema, a generated file, a provisioned object), and the tool in use will not reapply it:
    - Establish **what defeats reapplication** — a `--no-recreate`, a skip-if-exists, an immutable attribute — and require an explicit reconcile step. "The file is correct" is not evidence the running resource is.
    - Require the reconcile to be a whole-configuration comparison, not a hand-picked set of fields. A comparison of the two properties that happened to drift last time misses the next one added — a probe, a command flag, an environment value — and every future field joins the same blind spot.
    - Check the reconcile's own two edges: it must not churn on a clean start (a resource created moments ago is already current), and a failed reconcile must not be reported as success — an old resource that still answers its readiness check will otherwise read as reconciled, and the caller records a start that never applied the change.
    - WARNING; BLOCKER when the stale configuration is the one being tested, or when the resource serves other consumers during the window.

37. **An irreversible effect follows every refusal that can precede it** — when the change performs an effect it cannot undo (a push, a publish, a deploy, a delete, a send) and also refuses the call for one or more reasons:
    - Verify the refusal paths return **before** the effect, not after it. A helper that pushes first and then finds the branch belongs to another purpose has already changed the remote it then refuses to touch, and every later refusal shares that ordering.
    - Enumerate the refusals and the effect as one sequence, in the order the code runs them. "The check exists" is not the property; "no refusal can observe an effect it did not prevent" is.
    - Require the guard to pin the ordering, not just the outcome: assert the effect is absent on at least one refusal path, because a test that only reads the error message passes either way.
    - WARNING; BLOCKER when the effect publishes, deletes or rewrites something the caller cannot recover.

38. **A guard reads the value that takes effect, and every component of the identity** — when the change compares two things as equivalent before acting on one of them (a repository and a remote, an environment and a target, a directory and its link):
    - Read the value the operation will actually use. A push writes to a remote's **push** URL, not its fetch URL, and a symlinked path acts on its target: a guard that inspects the convenient one of the pair approves the wrong destination.
    - Compare every component that distinguishes the two. Owner and name are not an identity when the host may differ, and a path is not a target until it is resolved — an equality that drops a component admits a lookalike.
    - Refuse configurations the comparison cannot represent as one value (several push destinations, several roots) instead of silently validating one of them.
    - WARNING; BLOCKER when the approved destination receives an irreversible write.

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
> - **Recurring Issue Types (Generic)** — TOCTOU/concurrent modification? Config-like entity invariants? Migration `down()` restores exact schema? API contract round-trip? Docs match implementation (incl. docblocks)? Docs/runbooks issue only scoped, reversible commands? Architecture/design smells? Atomic commit structure? Configuration & rollout? Per-request performance? Deployment/queue rollout compatibility? Concurrent-race recovery guards the actual failing operation (`new()` vs `save()`)? Bootstrap path for newly-gated admin capabilities? Cached build artifacts renamed or invalidated when their inputs change? Request parameters validated rather than coerced? Blanket filters not defeating an always/never guarantee? Reused checkouts validated before writing? Generated refs unique under concurrency? Symlinked paths resolved before check/copy/stage?
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
