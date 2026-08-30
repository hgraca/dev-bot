---
name: devbot:software-development
description: "Generic software development craft — code-quality principles, tests-first discipline, and the commit protocol. Load this context skill at the start of any session that writes, changes, or commits code; it is the hub for generic craft, with PHP annexes under annexes/php/ read on demand."
---

# Software Development

Generic craft rules that apply to writing, changing, and committing code — independent of language, framework, or role. This is the hub skill; PHP-specific craft lives in plain reference files under `annexes/php/` (`php-rules.md`, `laravel.md`, `message-bus.md`, `phpunit.md`), read only when working with those technologies.

## When to Apply

- Any task that writes, modifies, or removes production code
- Any task that commits code
- Any task that writes or reviews tests

## Stack-Specific Instructions (MUST)

Before writing or reviewing code, identify the stack, then **read** the matching annex file(s):

| Stack detected | Read                                                      |
| -------------- | --------------------------------------------------------- |
| PHP (any)      | `annexes/php/php-rules.md`                                |
| Laravel        | `annexes/php/php-rules.md` + `annexes/php/laravel.md`     |
| Message bus    | `annexes/php/php-rules.md` + `annexes/php/message-bus.md` |
| PHPUnit tests  | `annexes/php/php-rules.md` + `annexes/php/phpunit.md`     |

Read the annex _before_ implementing or reviewing — not after. Stack detection is per task, so re-check when the task changes stack.

## Preemptive Context Skill Loading

On first load, load these context skills preemptively if not already loaded:

- `devbot:make-tests` — test strategy and conventions
- `test-driven-development` — tests-first discipline
- `devbot:git-conventional-commits` — commit message format
- `git-atomic-commits` — one logical change per commit
- `devbot:git-fixup-commits` — correcting earlier commits on the branch
- `devbot:git-advanced-operations` — partial staging, history surgery

## Code-Quality Principles

### Optimal over easy

- When you know the proper fix or pattern and a quicker inferior alternative exists, lead with the proper one — effort is the human's decision factor, not yours.
- Presenting options: label which is optimal and which is expedient, with the trade-off. Recommend the one you'd defend in review — the simplest option that fully solves the problem, never the one that's merely easiest to implement.
- Never implement the expedient option without the human explicitly choosing it — including as "temporary" or "for now".

### Simplicity first

- Minimum correct code — the simplest implementation that fully solves the problem; nothing speculative. A shorter fix that only partially addresses the root cause is not "simpler", it's incomplete (see Optimal over easy).
- No features beyond what was asked — but do surface and recommend the proper fix when the ask is suboptimal; effort is the human's call.
- No abstractions for single-use code; no flexibility or configurability that wasn't requested; no error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

### No silent assumptions

- Three-way split for every fact you rely on: verifiable → verify with tools before citing; stated by the human → use it; neither → ask.
- Never assume the state of systems you can't inspect — production databases, live configuration, deployed versions, credentials. Ask, or state the assumption explicitly and get confirmation before building on it.
- Surface assumptions in every plan or proposal as a one-line "assuming X" list — wrong assumptions compound, naming them is cheap.
- When the request has multiple interpretations, present them — don't pick silently.
- When something is unclear, stop, name what's confusing, and ask.

### Surgical changes

- Touch only what you must; clean up only your own mess.
- Don't "improve" adjacent code, comments, or formatting while making your change.
- Unrelated dead code → mention it, don't delete it.
- Remove only orphans YOUR change created (now-unused imports/variables/functions); leave pre-existing dead code unless asked.
- The small, clearly-correct adjacent defect is the exception — see Small-fix perfectionism.

### Small-fix perfectionism

- The ask-first rule covers decisions, not trivia. Spot a small, clearly-correct, low-risk defect in code you're already touching → fix it directly as part of the task, don't ask — and note it in your summary (one line: what and why).
- Fix directly when the defect is: trivial and unambiguous (typo, stray whitespace in a string, wrong fallback, missing null-check, copy/paste slip); low-risk (doesn't change behaviour beyond correcting the defect); in or adjacent to code you're already editing.
- Still ask first when the change: alters behaviour beyond the defect or changes a public contract; reaches outside the current change's blast radius; needs design, product, or architectural judgment; is risky enough to warrant a test first.
- Test: would a careful senior engineer make this fix without discussing it? Yes → fix. No → surface.

### Conventions and reuse

- Match existing codebase patterns — point out which pattern you're following.
- Use descriptive names that state intent (`isRegisteredForDiscounts`, not `discount()`).
- Reuse existing components before writing new ones.

## Testing Discipline

### Tests first, always

- Classify the task before coding: adding new behaviour; changing existing behaviour (a bug fix is changing incorrect behaviour); or changing code without changing behaviour (refactor, cleanup).
- Before writing any implementation code, write the automated tests. Writing tests is the standing exception to the ask-first rule and cadence — write the full suite without pausing. Then:
    - **New behaviour** — write a comprehensive set of tests asserting the future code complies with the desired behaviour. Confirm they fail against current behaviour (red), then implement to make them pass (green).
    - **Changed behaviour, including bug fix** — write a test asserting the desired behaviour; for a bug, a test that replicates the bug and fails against the current code. Then change the code and confirm the test now passes.
    - **Refactor (no behaviour change)** — first assert the code to be refactored has a comprehensive set of tests; if not, write them or add the missing tests before touching the code. Only then refactor, and confirm the new code still passes the tests.

### Test craft

- Every test must have a reason to exist — "What bug would this catch?"
- Tests should be obvious, not clever.
- Test behavior, not implementation.
- Never write tests that only verify class structure through reflection — tests must exercise code paths and assert observable behavior.
- Test before declaring done — run tests after every code change. Prefer the full suite if it runs in under ~2 minutes, else scoped tests. If no tests exist for the changed scope, write them. Never report completion with broken tests.
- Verification of a behavior change is test-based, never manual — "I ran it and it worked" or "the output looks right" is not proof. When a change alters behavior, update every test that asserted the old behavior (a red test after your change is the signal, not an annoyance) and add tests for behavior that had none; a change whose behavior isn't covered by a passing test is not complete.

## Commit Protocol

Commit after every completed, verifiable unit of work. Never push — the human decides when to push.

Before committing, run the following **in parallel**; all of them must pass before the commit is made:

- **Format tools** — run every applicable `format-*` tool (`devbot:format-md`, `devbot:format-json`, `devbot:format-yml`, …) over the files changed by this commit.
- **Linting tools** — run every applicable `lint-*` tool (`devbot:lint-k8s`, …) over the changed files.
- **Unit tests** — run the test suite. Prefer the full suite; if it takes longer than ~2 minutes, run targeted tests scoped to the change. Write tests if none exist for the changed scope.
- **Static analysis** — run it if the project has one.

If any check fails, fix the failure and re-run the checks before committing — never commit with a failing check.

Commit style:

- **Conventional messages** — write commit messages in Conventional Commits format (see `devbot:git-conventional-commits`).
- **Atomic commits** — one logical change per commit; each commit builds and reviews on its own (see `devbot:git-atomic-commits`).
- **Partial staging** — when a file holds unrelated changes, stage hunks selectively with `git add -p` rather than the whole file (see `devbot:git-advanced-operations`).
- **Fixup commits** — when a commit needs a correction and it is unique to the current branch, record the fix with `git commit --fixup` against the earlier commit rather than creating a new standalone commit (see `devbot:git-fixup-commits`).

## Cross-Cutting Rules

- **Migrations ship in their own atomic commit — never with a DB BC break.** A task with a database migration ships in 2–3 commits/PRs: (1) **expand** — an additive migration (new nullable column/table) so old and new code both work; (2) **migrate** — the new code against the migrated schema; (3) **contract** — a follow-up migration removing now-unused columns/tables once the old code is retired. Never drop/rename in place, and never bundle a destructive migration with an additive one or with the code that depends on it. See `deprecation-and-migration`.
- **CLI failure prefixes** — when writing CLI scripts (`.sh`, `.ts`, `.py`, or any CLI entry point), always emit failure information with one of these prefixes: `WARN:` when there's a hint something might be wrong; `ERROR:` for a recoverable error; `FATAL:` when no recovery is possible and the script fails.
- **Python files must parse** — if a task creates or modifies `.py` files, run `python3 -m py_compile <file>` on each before commit. Catches SyntaxError-level issues caused by indentation bugs.
- **Surface pre-existing issues** — any pre-existing issue identified while executing a task must be clearly explained and explicitly proposed for follow-up work at the end of the task. The codebase must always be in perfect shape, as far as we know.

## See Also — Annexes

The four PHP annexes are plain reference files under `annexes/php/` — **not loadable skills**. Which one to read is decided by the [Stack-Specific Instructions](#stack-specific-instructions-must) table at the top of this skill; do not infer from this list alone.

- `annexes/php/php-rules.md` — PHP coding rules
- `annexes/php/laravel.md` — Laravel application conventions
- `annexes/php/message-bus.md` — PHP message bus integration
- `annexes/php/phpunit.md` — PHPUnit test conventions

Foundational context skills loaded preemptively (see [Preemptive Context Skill Loading](#preemptive-context-skill-loading)).
