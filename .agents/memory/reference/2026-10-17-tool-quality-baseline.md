---
tags: [tooling, quality, assessment, baseline, devbot]
description: Baseline tool and skill grades before the 2026-10-17 quality pass, what changed, and a repeatable one-month re-assessment procedure.
date: 2026-10-17
---

# Tool-quality baseline — 2026-10-17

Use this note as the **before** snapshot. Re-run the assessment around **2026-11-17** and write a sibling report; the comparison is the point, not the raw numbers alone.

The changes described here are on PR **GET-E/dev-bot#2** (`feat/devbot-tool-quality`, 20 commits, squashed fixups). Merge and deploy before the re-assessment, otherwise the grades still describe the old tooling.

## 1. How the baseline was taken

| Item             | Value                                                            |
| ---------------- | ---------------------------------------------------------------- |
| Command          | `devbot stats --days=365`                                        |
| Scope            | all projects                                                     |
| Generated        | 2026-10-17                                                       |
| Grade rows       | 432                                                              |
| Tool columns     | 111                                                              |
| Source of grades | `devbot:grade-tools` → `<dev-bot>/.agents/logs/tools-grades.csv` |

**Grade scale** (from the grade-tools skill):

| Grade | Meaning                                                       |
| ----: | ------------------------------------------------------------- |
|     0 | Not used in the slice                                         |
|     1 | Used, outcome irrelevant / tool limitation                    |
|     2 | Used, marginal or redundant                                   |
|     3 | Used, helpful, but a real substitute existed                  |
|     4 | Significant contribution; hard to replace                     |
|     5 | Critical; outcome would have been materially wrong without it |

**Distribution over used cells:** 4 = 64%, 3 = 19%, 1–2 = 9%, 5 = 7%. The matrix is lenient and self-assessed. In particular, **3 is structurally guaranteed for thin convenience wrappers** (`format-*`, `tree`, `git-report`, `list-projects`) whenever a shell or prettier substitute exists. Do not treat “average 3.3” as a failure for those tools; track their **1–2 rate** and the specific failure notes instead.

## 2. Baseline — what was working

| Tool                           |  Avg | Uses | Min |    σ | Read                                       |
| ------------------------------ | ---: | ---: | --: | ---: | ------------------------------------------ |
| `devbot:review-implementation` | 4.73 |   56 |   4 | 0.44 | Workhorse; never disappointed              |
| `devbot:gather-context`        | 4.69 |  119 |   4 | 0.46 | Workhorse; only its mandatory filler hurt  |
| `signoz`                       | 4.62 |   78 |   1 | 0.66 | High value, occasional outages             |
| `datasources`                  | 4.40 |    5 |   4 | 0.49 | Decisive when used                         |
| `datasources-mariadb-prod`     | 4.29 |    7 |   4 | 0.45 | Decisive live data                         |
| `websearch`                    | 4.14 |   37 |   3 | 0.47 | Good pointer; not a source of truth        |
| `devbot:address-review`        | 4.06 |  101 |   2 | 0.42 | Strong workflow; fixup edge cases          |
| `devbot-tools:search-memories` | 3.98 |  354 |   2 | 0.61 | Most-used custom tool; trust was the issue |
| `devbot:grade-tools`           | 3.98 |  328 |   3 | 0.21 | Procedural; consistent                     |
| `devbot:software-development`  | 3.94 |  252 |   1 | 0.52 | Craft hub; partly duplicated by the prompt |

**Guardrail for next time:** `review-implementation` and `gather-context` must stay ≥4.6 with min ≥4. If either drops, the quality pass damaged the context/review loop.

## 3. Baseline — the improvement set

| Tool                              |  Avg | Uses | Min |    σ | Main diagnosis                                                      |
| --------------------------------- | ---: | ---: | --: | ---: | ------------------------------------------------------------------- |
| `graphify`                        | 1.86 |   57 |   1 | 0.83 | Empty/stale/disabled graph; still mandated by gather-context        |
| `customize-opencode`              | 2.00 |   43 |   1 | 1.03 | Preloaded in dev-bot; irrelevant unless editing harness config      |
| `devbot:explicit-architecture`    | 2.00 |   31 |   1 | 1.05 | Preloaded; placement-only; repo uses PhpArkitect                    |
| `devbot:git-advanced-operations`  | 2.33 |   58 |   1 | 1.09 | Preloaded; rare history surgery; overlaps fixup/atomic              |
| `devbot:make-adr`                 | 2.50 |    8 |   1 | 0.71 | Hardcoded `.ai/local/ADRs/ADR-NNN` instead of the vault layout      |
| `codebase-memory`                 | 2.75 |   65 |   1 | 0.91 | Project-id discovery, stale index, narrow scope, dead semantic path |
| `devbot:makefile`                 | 2.76 |   75 |   1 | 0.94 | Assumed an app container; wrong for host-run BATS and worktrees     |
| `devbot:codebase-index`           | 2.85 |   13 |   1 | 0.95 | Engine-selection confusion; MCP often unavailable                   |
| `devbot:make-tests`               | 2.91 |   58 |   1 | 0.97 | PHP-shaped `tests/Unit` + `tests/Integration`; preloaded            |
| `devbot:architecture-rules`       | 3.00 |   24 |   2 | 0.71 | DDD/PHP-shaped; off-target for TS/shell/config                      |
| `devbot-tools:lint-k8s`           | 3.00 |   14 |   2 | 0.76 | CRD schema gaps, pre-existing noise, no changed-only mode           |
| `incremental-implementation`      | 3.20 |   15 |   2 | 0.65 | Duplicated `software-development`                                   |
| `test-driven-development`         | 3.26 |   47 |   1 | 1.12 | Duplicated `software-development`; preloaded                        |
| `devbot:git-fixup-commits`        | 3.29 |   96 |   1 | 1.20 | Pushed/default/nested-fixup cases missing                           |
| `devbot-tools:format-json`        | 3.29 |   41 |   1 | 0.59 | Thin prettier wrapper; silent no-op                                 |
| `devbot:documentation-rules`      | 3.30 |   43 |   1 | 1.00 | Described only the dev-bot docs site                                |
| `devbot-tools:format-md`          | 3.31 |  163 |   2 | 0.49 | Thin prettier wrapper; silent no-op; hook overlap                   |
| `devbot-tools:list-projects`      | 3.32 |  127 |   1 | 0.86 | Unfiltered 27-project dump, forced into every gather                |
| `devbot-tools:tree`               | 3.34 |   83 |   2 | 0.66 | `tree -a`, no excludes: `.git`, `node_modules`, `vendor`            |
| `devbot-tools:format-yml`         | 3.35 |   17 |   2 | 0.59 | Same wrapper story                                                  |
| `planning-and-task-breakdown`     | 3.36 |   22 |   2 | 0.64 | `tasks/plan.md` conflicts with the vault work folder                |
| `devbot-tools:reindex-memories`   | 3.36 |   14 |   2 | 0.81 | “prune” was described as a cheap pass but is a full rebuild         |
| `debugging-and-error-recovery`    | 3.36 |   11 |   1 | 0.88 | Restated `software-development`                                     |
| `devbot:shell-strategy`           | 3.52 |  354 |   1 | 0.63 | Mostly inert; `/dev/null` rule breaks TTY containers                |
| `devbot-tools:git-report`         | 3.58 |  145 |   1 | 0.66 | Bound to the MCP server cwd; cannot target siblings/worktrees       |
| `devbot:git-conventional-commits` | 3.63 |  128 |   1 | 0.68 | Overlaps `git-commits`; derivable from history                      |
| `devbot:git-atomic-commits`       | 3.63 |  112 |   1 | 0.79 | Overlaps `git-commits`/`software-development`                       |
| `devbot:gh-create-pr`             | 3.72 |   18 |   2 | 0.56 | `@copilot` reviewer example was wrong; update path out of scope     |

**Preload tax:** the dev-bot repo preloaded **8 skills per session**, and `software-development` preloaded five more technique skills. `customize-opencode` (2.00), `makefile` (2.45 in the dev-bot view) and the git trio were mostly unused per session.

**Raw usage, 90 days:** 5,479 `skill` calls (5.4% of all calls, ~393M tokens); 2,244 `search-memories`, 686 `format-md`, 391 `git-report`, 347 `list-projects`, 319 `tree`.

## 4. What changed in the 2026-10-17 pass

### Measurement

- Duplicated `devbot-tools:devbot-tools:*` columns are canonicalised, so one tool has one history.
- `record-grades.py --last-row` replaces hand-written CSV filtering when choosing the grading slice.
- Legacy backfilled zeros no longer hide a real grade in the merged column.

### Preload and context gathering

- The dev-bot repo preloads only `software-development` + `git-commits` (was 8).
- `software-development` preloads only `git-commits`; technique skills load from their own triggers.
- `gather-context` lists siblings only for cross-repo work, queries graphify only when the graph is populated, and reports an unavailable/stale codebase engine in one line.

### Tool contracts

| Tool                  | Change                                                                                                                                                                       | Signal to watch next month                                                               |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| `tree`                | Default excludes (`.git`, `node_modules`, `vendor`, caches), depth 3, `--all`, `--exclude`                                                                                   | Fewer noise notes; avg up; no “dumped .git objects” comments                             |
| `format-md/json/yml`  | `N checked, M changed` summary; `--check` (exit 1/2, fail closed); CRLF preserved; batch errors fail the run                                                                 | No “silent no-op” notes; `--check` trusted in CI                                         |
| `list-projects`       | `--filter`, `--only`, `--compact`; invalid regex/unknown flags rejected                                                                                                      | Fewer “27 irrelevant projects” notes; usage may drop intentionally                       |
| `git-report`          | `--cwd` for sibling/worktree; always prints repository path; non-repo target is an error                                                                                     | Zero wrong-repo notes; fewer stale-worktree notes                                        |
| `lint-k8s`            | Missing CRD schemas skipped unless `--schema`; `--changed`/`--base`; options after path; clean `--json --changed`                                                            | Fewer CRD false errors; changed-only reviews usable; no silent base-typo pass            |
| `agent-communication` | Empty input is an explicit “nothing to validate” result                                                                                                                      | No “meaningless OK” note                                                                 |
| `search-memories`     | Indexes the whole memory tree (`latent`, `work`, `thinking`, `active`); per-index root detection; stale-vs-empty note; HEAD-drift warning; qmd migration; corpus fingerprint | Fewer false “no matches” when a note exists; stale results labelled; HEAD drift surfaced |
| `reindex-memories`    | `prune` described as the incremental rebuild it is; status guidance                                                                                                          | No “cheap self-heal” mismatch                                                            |

### Skills

- `makefile`, `make-tests`, `documentation-rules`, `make-adr`: detect the repository layout before prescribing container paths, test locations, docs layout, or ADR filenames.
- `git-fixup-commits`: situation/action table for nested fixups, pushed/default branches, cross-repo notes.
- `address-review`: group findings that edit the same hunk; skip the approval gate only on an explicit autonomy grant.
- `codebase-memory` / `graphify`: preflight project id, index freshness, empty graph, unreachable gateway; explicit grep/read fallback.
- `software-development`: official docs (context7/webfetch) for library questions.
- `use-case-map`: end-to-end flow triggers.
- `shell-strategy`: TTY exception for `docker compose exec`/`make up`.

## 5. Re-assessment procedure (run around 2026-11-17)

1. **Deploy first.** Merge PR #2, run `devbot update` and `devbot reinit` in the projects that should get the new behavior. Confirm `devbot list skills` shows the reduced preload list.
2. **Capture the same views:**
   ```bash
   cd /home/herberto/Development/Get-e/dev-bot
   devbot stats --days=90  > /tmp/tool-quality-90d.md
   devbot stats --days=30  > /tmp/tool-quality-30d.md
   devbot stats --days=90 --project "$PWD" > /tmp/tool-quality-devbot-90d.md
   ```
   Use 90 days for stable averages and 30 days for recent movement. Always state the window and scope.
3. **Fill the comparison table** (below) from the Tool Grades table. Use the canonical tool names; the duplicate-prefix columns should be gone.
4. **Read the Poor ratings section** for every row in the improvement set. Sample up to five notes per tool and classify them:
   - tool limitation
   - configuration/usage issue
   - improvement/removal signal
5. **Count 1–2 grades** per targeted tool. For convenience wrappers this matters more than the average; a 3 is expected.
6. **Check usage movement:**
   - `tree`, `git-report`, `format-*`, `search-memories`: usage should hold or rise if the fixes worked.
   - `list-projects`, `customize-opencode`, `explicit-architecture`, `git-advanced-operations`: usage may fall deliberately (conditional/lazy loading). A fall is only a problem if the tool was genuinely needed and skipped.
   - `skill` calls per 90 days: target a visible reduction after the preload cut, without lowering `review-implementation`/`gather-context`.
7. **Guard the suite:** run the full `make test` from a clean worktree with `DEV_BOT_ROOT=<worktree>`; require exit 0 before trusting the quality verdict.
8. **Decide per tool:** improved / flat / worse. Apply the decision rules below and write a sibling report named `YYYY-MM-DD-tool-quality-assessment.md`, linking back to this note.

### Comparison template

| Tool                      | Baseline avg / uses / min | 90-day avg / uses / min | Δ avg | 1–2 rate before → after | Main note themes | Verdict |
| ------------------------- | ------------------------- | ----------------------- | ----: | ----------------------- | ---------------- | ------- |
| `graphify`                | 1.86 / 57 / 1             |                         |       |                         |                  |         |
| `customize-opencode`      | 2.00 / 43 / 1             |                         |       |                         |                  |         |
| `explicit-architecture`   | 2.00 / 31 / 1             |                         |       |                         |                  |         |
| `git-advanced-operations` | 2.33 / 58 / 1             |                         |       |                         |                  |         |
| `make-adr`                | 2.50 / 8 / 1              |                         |       |                         |                  |         |
| `codebase-memory`         | 2.75 / 65 / 1             |                         |       |                         |                  |         |
| `makefile`                | 2.76 / 75 / 1             |                         |       |                         |                  |         |
| `codebase-index`          | 2.85 / 13 / 1             |                         |       |                         |                  |         |
| `make-tests`              | 2.91 / 58 / 1             |                         |       |                         |                  |         |
| `architecture-rules`      | 3.00 / 24 / 2             |                         |       |                         |                  |         |
| `lint-k8s`                | 3.00 / 14 / 2             |                         |       |                         |                  |         |
| `git-fixup-commits`       | 3.29 / 96 / 1             |                         |       |                         |                  |         |
| `format-json`             | 3.29 / 41 / 1             |                         |       |                         |                  |         |
| `documentation-rules`     | 3.30 / 43 / 1             |                         |       |                         |                  |         |
| `format-md`               | 3.31 / 163 / 2            |                         |       |                         |                  |         |
| `list-projects`           | 3.32 / 127 / 1            |                         |       |                         |                  |         |
| `tree`                    | 3.34 / 83 / 2             |                         |       |                         |                  |         |
| `format-yml`              | 3.35 / 17 / 2             |                         |       |                         |                  |         |
| `reindex-memories`        | 3.36 / 14 / 2             |                         |       |                         |                  |         |
| `shell-strategy`          | 3.52 / 354 / 1            |                         |       |                         |                  |         |
| `git-report`              | 3.58 / 145 / 1            |                         |       |                         |                  |         |

Also record the guardrails: `review-implementation` and `gather-context` ≥4.6 / min ≥4; `make test` exit 0.

## 6. Decision rules

- **Fix or retire** a tool that stays **≤3.0 with ≥20 uses** for two consecutive monthly assessments and whose 1–2 rate has not fallen.
- **Keep** a convenience wrapper at 3.x if its 1–2 rate is near zero and its notes no longer mention silent no-ops or wrong targets. Its ceiling is the rubric, not the implementation.
- **Investigate before removing** a tool whose usage fell: distinguish “conditional gathering worked” from “agents stopped finding it”.
- **Retire graphify** if it remains ≤2.0 after the preflight/conditional changes; keep the CLI for explicitly graph-aware repositories.
- **Keep the preload cut** if `review-implementation`/`gather-context` hold and `skill` calls fall; revert individual entries if a real trigger misfires.
- **Never** declare improvement from usage alone: a tool can be used more often and still be wrong.

## 7. Caveats

- Grades are self-assessed and lenient; 64% were 4s at baseline. Compare like with like.
- The duplicate-column merge changes how the matrix is read. Baseline numbers above were captured before the merge; after it, one canonical row per tool is the correct comparison.
- The grade CSV is install-level (`all projects`), not per-project; the dev-bot-only view differs. State the scope in every report.
- A month is short for tools used a few times a month. Treat `uses < 5` as unproven, not improved.
- Agent population, project mix, and seasonality affect both usage and grades. A drop in `list-projects` usage is expected; a drop in `search-memories` usage is not.
- The 2026-10-17 pass touched tooling and skills, not application code. Do not attribute product bugs to it.

## 8. Baseline one-liner for the next report

> On 2026-10-17, over 432 grade rows and a 365-day window, the workhorses were `review-implementation` (4.73), `gather-context` (4.69) and `signoz` (4.62); the worst ROI was `graphify` (1.86), `customize-opencode` (2.00) and `explicit-architecture` (2.00). The pass cut the dev-bot preload list from 8 skills to 2, fixed the convenience-tool contracts (`tree`, `format-*`, `list-projects`, `git-report`, `lint-k8s`), and made memory search cover the whole memory tree with stale/migration/freshness safeguards.
