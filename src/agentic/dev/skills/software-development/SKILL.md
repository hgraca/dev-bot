---
name: devbot:software-development
description: "Load at session start in every project where code is written, changed, or committed. Use when writing, changing, or reviewing code."
---

# Software Development

Generic craft rules that apply to writing, changing, and committing code — independent of language, framework, or role. This is the hub skill; PHP-specific craft lives in plain reference files under `annexes/php/` (`php-rules.md`, `laravel.md`, `message-bus.md`, `phpunit.md`), read only when working with those technologies.

## When to Apply

- Any task that writes, modifies, or removes production code
- Any task that commits code
- Any task that writes or reviews tests

## Workflows

A workflow is the end-to-end way a task is carried through the project: how it starts, where its
commits land, how it is reviewed, and where it stops. Select it in this order — the first match wins:

1. **Explicit user instruction** — when the user names a workflow or asks to deviate from the
   configured one, follow it for that run.
2. **Project configuration** — the `workflow` key in `.devbot.project.jsonc`, falling back to that
   same file's not-yet-migrated `worktrees` key (`true` → `worktrees`, `false` → `trunk`), then to
   `.devbot.global.jsonc` in the same order. In a `supervisor: true` session _the project_ is the
   **owning project** of the task's files — resolve it first (`devbot tool project-for-path <path>`),
   never the supervisor root, and run the workflow's repo-scoped steps in that owner.
3. **Default** — the [Worktrees workflow](#worktrees-workflow) when no configuration names one.

**Check in after every step.** In an interactive session, end each step with a two-line report — what
you did and what comes next — and ask the user whether to continue or change something. Do not start
the next step until they answer. Runs with no human to answer are the only exception:
`devbot:work-autonomously` skips the check-ins, and a delegated subagent reports to its orchestrator
instead.

### Worktrees workflow

The default. Each task gets its own branch in a linked worktree and is carried to an open pull
request; nothing is merged.

1. **Resolve the task** — the task is what the user asked for, or the content of a file path or URL
   they gave. With nothing to go on, ask before doing anything else.
2. **Assess progress** — never assume a fresh start. Collect the default branch, the commits already
   on the task's branch, any pull request in **any** state (`gh pr list --head <branch> --state all --json number,url,state,mergedAt` — a query restricted to open pull requests cannot tell a merged or closed one from none at all), and `git status --porcelain`; report the state in three lines and resume at the first incomplete step. The branch is the task's identity:
   continue it rather than cutting a new one, never reopen a closed pull request, and never stash or
   discard changes that are not this task's.
3. **Work in the task's worktree** — when the assessment found the task already in a linked
   worktree, continue there; never create a second one. Only when the task is not in a worktree yet,
   create it before the first edit from the main checkout (`worktree.sh create <branch>` per
   `devbot:git-worktrees`). All edits use the worktree's absolute paths and all git commands run
   with `-C <worktree>`.
4. **Work the task** — implement what remains of it in small atomic commits
   (`devbot:git-atomic-commits`).
5. **Self-review** — when the task is done, delegate a review of the whole changeset against the
   default branch to the session's code reviewer, following the session's review gate (DevBot asks
   the user first and delegates to `@reviewer`; an autonomous run delegates straight away to
   `@code-reviewer` as `devbot:work-autonomously` directs), and address every finding as your own
   recommendation (`devbot:address-review`).
6. **Open the pull request and run the review loop** — push the branch and open the pull request with
   `devbot:gh-create-pr`, then loop until a review introduces no new findings: request the reviewer,
   read both the line comments and the review body, fix each finding as a fixup, and reply then
   resolve each thread. `devbot:work-autonomously` carries the loop's cadence and reviewer-effort
   mechanics.
7. **Hand back** — stop and report the pull request. The reviewer squashes the fixups and merges; you
   never merge it.

### Trunk workflow

Work directly on the default branch, review locally, and stop for the user's gate before pushing.
There are no pull requests. The worktree-first rule in `devbot:git-worktrees` belongs to the
Worktrees workflow; this one commits on the default branch.

1. **Resolve the task** — as in the Worktrees workflow.
2. **Assess progress** — collect the default branch, the commits not yet pushed, and
   `git status --porcelain`; report the state in three lines and resume at the first incomplete step.
   When the checkout is not on the default branch, stop and ask whether to switch to it or to follow
   the Worktrees workflow instead.
3. **Work on the default branch** — implement what remains of it in small atomic commits
   (`devbot:git-atomic-commits`). No branch, no worktree, no pull request.
4. **Self-review** — delegate a review of the commits against `origin/<default>` to the session's
   code reviewer under the same gate, and address every finding as your own recommendation
   (`devbot:address-review`).
5. **Hand back before the push** — stop and report. The user gates the push to `origin/<default>`;
   you never push the default branch yourself.

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

On first load, load `devbot:git-commits` preemptively if it is not already loaded — every commit
depends on the shared rules it carries.

Do **not** preload the other commit-technique or test skills. They fire from their own triggers:

- `devbot:git-conventional-commits` — when wording a commit message
- `devbot:git-atomic-commits` — when splitting or ordering commits
- `devbot:git-fixup-commits` — when correcting a commit unique to the branch
- `devbot:make-tests` — when writing tests or choosing a test strategy
- `test-driven-development` — when implementing logic or fixing a bug

## External documentation

For a library, framework, SDK or API question, prefer the official documentation over memory:
use `context7` (`resolve-library-id` → `query-docs`) when the MCP is available in this project;
otherwise fetch the vendor docs with `webfetch`/`websearch`. Check the installed version first — a
docs answer for the wrong major version is worse than no answer.

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

### Comments

- **The _why_ belongs in the commit description, not the code.** A comment explaining why a line exists, what workaround it encodes, or what would break without it is a commit-body line in the wrong file — invisible to `git log`, and a duplicate of the message. Put the reasoning in the body; reserve in-code comments for the 1–2 lines of mechanics a reader genuinely cannot infer.
- **No prose in the middle of code.** Narration ("now we iterate and build the map…") restates what the code already says and rots as it moves. Let names and structure carry the meaning; delete the rest.
- **Docblocks only when they earn their place** — the function/method signature is not self-documenting (non-obvious contract, side effects, ordering, units, a surprising return), or a static-analysis tool requires one. A docblock that merely restates the name and parameters is noise.
- **At most 1–2 lines for genuinely unreadable code** — a little-known native function or a dense chain of calls. Prefer instead to extract it into a function with a short, meaningful name (≤ ~32 chars): the name states the intent, and the extraction is testable.

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

Commit after every completed, verifiable unit of work. Never push the default branch; push a task
branch only where the selected workflow directs (see [Workflows](#workflows)), and the human decides
when.

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
- **Fixup commits** — when a commit needs a correction and it is unique to the current feature branch, record the fix with `git commit --fixup` against the earlier commit rather than creating a new standalone commit. This is the required form on a feature branch; the fixups are squashed into their targets before the branch is merged (projects commonly enforce this with a no-fixup CI guard) and must never be recorded on the default branch itself (see `devbot:git-fixup-commits`).

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
