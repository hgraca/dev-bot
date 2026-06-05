---
name: implement-story
description: "Implements an approved plan by orchestrating Tester, Developer, and Reviewer in a structured cycle per task. Use this skill after the human stakeholder approves the plan produced by the make-plan skill."
---

# Skill: Implement Plan

Implement approved plan by orchestrating Tester, Developer, and Reviewer for each task in backlog.

## When to Apply

- After human stakeholder approves plan from `plan` skill
- `/implement` command invoked for implementation
- `/test`, `/dev`, or `/review` command invokes specific step

## Artifacts

Place all artifacts in `<issue-folder>` established during planning (see `plan` skill for naming conventions). Artifacts MUST NOT be committed to git.

### Scratch files

When needing temporary file, use `thinking` skill. Promote useful findings to latent/ files before closing session.

### Pre-flight check

Before creating any artifact, verify issue folder already exists in `.agents/memory/work/active/`. If it does NOT, STOP — planning must be completed first via `plan` (or, for trivial work routed directly to implementation, orchestrator must create work folder before invoking this skill). If multiple folders exist for same initiative, consolidate into correctly-named one and delete duplicate.

## Clarification Channels

If developer needs:

- Specification clarification: consult product owner (via orchestrator)
- Technical guidance: ask architect first; if inconclusive, ask human stakeholder

## Procedure

### Step 0: Pre-flight

1. **Story-domain memory search**: Read latent/ notes per `search-memory` skill with story-topic keywords. Identify entries relevant to current scope.

2. **Surface-keyword memory search — MUST**: Before delegating any task to @developer, extract from the task's technical actions the **implementation surface**: file types modified (e.g. `Dockerfile`, `php-fpm`, `www.conf`, `compose.yml`), technologies touched (e.g. `env[]`, `printf`, `sed`), and patterns applied. Run a second `search-memories` with those surface terms — NOT story-domain terms. If latent notes with matching `trigger-on` or `keywords` fields are found, include them in the developer delegation prompt under a `## Relevant latent notes` section. This catches gotchas that are invisible to story-scoped queries (e.g. a PHP-FPM env[] note won't surface when searching "opentelemetry" but will surface when searching "php-fpm www.conf env").

3. Include applicable lessons from both searches in delegations to Developer, Tester, and Reviewer.

### Step 1: Provide plan

Provide plan (`backlog.md` and any architecture/UI specifications) to @developer.

### Step 2: Task cycle

For each task in backlog:

1. **Test** — Delegate to @tester:
    - Before delegating, check whether the expected test file already exists (e.g. `tests/<name>/test-<task>.sh`). If it does, skip Tester delegation and proceed to Developer.
    - Create test for each acceptance criterion
    - Create additional automated tests deemed necessary
    - When tests involve parsing structured text (frontmatter, markdown, YAML, config files), always include edge cases: valid input, missing/absent structure, and malformed structure (e.g. test with frontmatter, without frontmatter, and with malformed frontmatter).
    - For infrastructure tasks (shell scripts, YAML configs, markdown) where unit tests do not apply, create simple integration test (e.g. `test-init.sh` pattern) validating install/init/doctor chain programmatically. If no integration test feasible, document why in session report.
    - **Config-test ordering** — for tasks where tests are grep-based config validation (checking YAML keys, Makefile targets, file existence), consider delegating tester AFTER developer so grep patterns match actual implementation rather than speculative predicted output. Speculative patterns cause false negatives and tester stalls that waste debugging cycles. If a test script already exists as a stub with `# TODO:` markers, extend it post-implementation.
    - Save session report to task folder, signal [FINISHED] with report

2. **Implement** — When Tester finished, delegate to @developer:
    - Implement task following plan
    - Ensure tests pass before considering task complete
    - **Commit changeset** before signalling [FINISHED] — use `git add <specific-files>` (never `git add -A` or `git add .`), verify `git diff --staged --stat`, then commit with clear message
    - **Verify git index health when committing 10+ new files** — Run `git fsck` before `git add`. If `invalid object` errors appear, recover with `git rm --cached <affected-file>` and re-stage. This prevents index corruption from rapid file creation across multiple delegations.
    - If task introduces new user-facing feature (plugin, tool, command, skill), create documentation page even if task description does not explicitly require it. Follow existing doc structure in `docs/`.
    - Signal [FINISHED] with a one-line summary of what was committed (e.g. "Committed: feat(litellm): add install.sh — 3 files, 20 assertions pass")

3. **Review** — When Developer finished, delegate to @reviewer:
    - **Gate**: If task modifies 2+ files (excluding test fixtures, config files, and markdown docs), reviewer delegation is REQUIRED — MUST NOT skip. Single-file changes that are purely wiring, config, or documentation may skip reviewer delegation at orchestrator's discretion.
    - Save Review Report to task folder, signal [FINISHED]

4. **Address findings** — When Reviewer finished, delegate to @developer to address issues. Developer MUST commit fixes before signalling [FINISHED]. After fixes committed, create architecture spec addendum file referring differences from architecture spec plan to actual final implementation. Iterate from step 2.3 until no remaining issues.

5. **Mark done** — Set task title in _strikethrough_ in `backlog.md`.

6. **Progress report** — Output to human stakeholder:

    > **Progress**: \<completed\>/\<total\> tasks done | \<blocked\> blocked | \<remaining\> remaining

7. **Capture lessons** — When task complete, follow `remember_task` skill immediately. Do not defer to end of session.

8. Move to next task from step 2.1.

### Step 3: Completion

When all tasks done:

1. Verify test coverage has not regressed. If it has, create follow-up task before approval.
2. Produce post-iteration retrospective using `make-retrospective` skill.
3. Address retrospective findings using `address-retrospective` skill — pass retro file path.
4. Approve or reject.
5. When all tasks done, follow `remember_task` skill to capture lessons learned.
6. Notify human stakeholder with completion report and recommended next actions.
7. Archive issue folder: move `<issue-folder>` from `.agents/memory/work/active/` to `.agents/memory/work/archive/`, preserving its name.
8. Proceed with non-destructive closure actions immediately without asking permission.

## Delegation Rules

- Invoke Tester, Developer, and Reviewer as separate subagents — never merge into single delegation.
- Limit each developer delegation to at most 3 tasks.
- When delegating multiple backlog tasks to developer, include any story-level technical actions (from the backlog's `### Story-level technical actions` section) as additional items in the prompt. Story-level actions sit outside individual tasks — developer won't see them otherwise.
- Include concrete class signatures, constructor parameters, file paths, and dependency details from existing codebase.
- Include only context relevant to specific task — not entire project context. Summarize large files. Load one skill per delegation.
- All code changes — including trivial review fixes — MUST be delegated to Developer. Orchestrator MUST NEVER apply code changes directly.
- **Documentation-only tasks** (markdown-only, no code changes, combined output ≤200 lines) may be handled directly by orchestrator without developer delegation. Orchestrator MUST still follow `documentation-rules` skill. This exception does not apply if the doc task requires reading analysis output from a code task — delegate to Developer in that case.
- When delegating plugins or JS/TS code, state project's import conventions explicitly (e.g. "Use bare `fs`/`path` imports, not `node:fs`/`node:path`"). Reference existing plugin files as style examples.
- When delegating code that loops over filesystem operations (readFileSync, writeFileSync, readdirSync), explicitly require: "Wrap filesystem operations in try/catch — single failure MUST NOT abort entire loop." Point to reference implementations that demonstrate this pattern.

## Exception Handling

- When unexpected situation arises, use `exception-handling` skill for structured recovery.
- If developer session stalls or produces no usable output:
    1. Inspect working directory for partial progress
    2. Re-delegate only incomplete work to fresh session with explicit specifications (concrete class signatures, constructor parameters, test file locations)
    3. Never re-delegate already-completed work
- Orchestrator may terminate early if requirements change or task deprioritized.

## Parallelization

By default, tasks execute sequentially (Tester -> Developer -> Reviewer per task). Run independent tasks in parallel only when **all** criteria met:

### Eligibility

1. **No shared files** — Tasks do not modify same files or directories.
2. **No dependency** — Neither task output is other task input.
3. **No shared state** — Tasks do not modify same database tables, configuration, or service registrations.
4. **Self-contained tests** — Each task tests can run independently without other task code.

### How to Parallelize

1. Identify eligible parallel tasks from backlog.
2. Delegate each task to separate Developer session simultaneously, each with its own Tester and Reviewer cycle.
3. Each parallel track follows full task cycle (step 2.1–2.4) independently.
4. After all parallel tracks complete, run full test suite to verify no integration conflicts.
5. If conflicts arise, create follow-up task to resolve them sequentially.

### When NOT to Parallelize

- Tasks that modify same bounded context domain layer
- Tasks where one introduces new abstraction that other consumes
- Database migrations (always sequential to avoid ordering issues)
- Tasks where Architect plan specifies explicit ordering

## MUST

- Run retrospective (Step 3.2) in same session as final commit — do not defer to later session.
