---
title: "Forensics"
description: "Behavioral code analysis over version-control history — hotspots, temporal coupling, ownership, trends and commit-history intelligence, after Tornhill's Code as a Crime Scene."
commands: ["forensics-report"]
skills: ["forensics"]
tools: ["forensics"]
---

Investigates how a codebase has _evolved_ rather than how it looks right now: it mines git history and per-language static metrics into a SQLite store, then reports where technical and organizational risk repeatedly appears.

```bash
devbot tool forensics run <repo> --since 2025-09-01 --until 2025-09-30 \
  --out <repo>/.forensics/report-2025-09.md
```

`run` mines and reports in one step, into **one** self-contained Markdown file.
`mine` writes the store alone, `analyse` queries a single view, and `report <db>`
renders a store that already exists — its `--out` takes a directory or a file path.

Every metric is bound to the window `mine` ran with — the last calendar month by
default, or whatever `--since`/`--until` say. `--all` lifts the bound and mines the
whole history; it cannot be combined with `--since`/`--until`. Bounds take
`YYYY-MM-DD` or ISO-8601, interpreted in UTC — a date-only value means that UTC day,
not git's approximate forms like `"last year"`. The window is recorded in the store,
so a report's time base is never ambiguous within that store.

Mined history is selected on **committer** date (git's walk), and the dates the report
prints are those committer dates, so every window-scoped figure agrees with the
selection. The `commits` activity command keeps **author** dates instead — a rebased or
backdated commit can appear in one and not the other.

## The report

`run` (and `report <db>`) write one Markdown document holding everything:

- a **Data quality** block first — each source the run could draw on, its count, and how
  to enable it when absent. An optional source (`--defects <csv>`, `--trends`,
  `--modules name=prefix,...`) that was not supplied leaves the sections it feeds empty,
  and this block states that rather than leaving it to be guessed from an `_(none)_`
  table.
- every view, each carrying whatever caution its emptiness needs — boundary coverage
  under Modules, the composition-root exclusion under Structural coupling.
- **Commit activity**, and with `--with-prs` the merged-PR activity. A report rendered
  without an authenticated `gh` still succeeds, noting the PR section is unavailable.
- **Time to fix**, then the methodology footer.
- with `--with-analysis`, an empty **Analysis & recommendations** section — the shape an
  agent fills in with its own reading of the figures: refactoring targets, bus factor and
  knowledge sharing, and the limits the Data-quality block names.

The `/devbot:forensics-report` command does that for a project end to end: it asks for the
time window, runs the tool, and writes the analysis itself.

## What it produces

- **Hotspots** — complexity × change rate, ranked; the refactoring priority list.
- **Debt priority** — a composite of change, complexity, coupling, defect rate and ownership risk, with every component exposed per file.
- **Complexity trends** — how a file's complexity grows across sampled revisions (`mine --trends`), sampled only inside the window at a `day|week|month|quarter|year` interval.
- **Change rate** — commits and commits-per-active-day per file.
- **Temporal coupling** — files that change together without a structural dependency.
- **Ownership & concentration** — authors per file and per unit, top-author share, bus factor.
- **Defects & risk** — SZZ defect origin, time-to-fix, external defect counts (`mine --defects <csv>`), and risk = hotspot × defects.
- **Commit-history intelligence** — conventional-commit mix (overall and per author), tickets, commit-process metrics and release cadence, boxed to a date range, with author identities folded through the repository's `.mailmap`.
- **Activity metrics** — pull requests merged and commits, per author plus a repo total, boxed to a date window (default: the last month), through a provider adapter so GitHub ships now and GitLab can follow.
- **Architecture vs organization** — cross-module coupling and ownership diffusion (`mine --modules name=prefix`), plus class-level structural coupling.
- **Report formats** — Markdown, JSON, CSV (per view) or a self-contained HTML page with a hotspot map.

## Architecture

A language-agnostic core (`tools/forensics.sh` + `lib/forensics-lib.py`) owns git mining, storage, analysis and reporting. Language specifics live behind `langs/<lang>/plugin.sh`, which answers a four-verb contract:

| verb        | purpose                                                                       |
| ----------- | ----------------------------------------------------------------------------- |
| `meta`      | declare `lang`, `extensions`, `capabilities`, `unit_kinds`, `metrics`         |
| `doctor`    | report the resolved engine (project copy → scratch install) + container image |
| `provision` | install a pinned engine into `storage/forensics/<lang>`                       |
| `units`     | emit code units + static complexity as canonical JSON                         |

Four languages ship: `php` (PDepend), `ts` (TypeScript compiler API), `java` (JDK compiler tree API) and `go` (stdlib `go/ast`). Adding another is one `langs/<lang>/` directory answering the same four verbs.

Engines are provisioned on demand with `forensics provision --lang <lang>`: TypeScript and PDepend install into `storage/forensics/` (npm / Composer), Go pulls `golang:1.22-alpine`, and Java uses the host JDK or a pulled `eclipse-temurin` image. A missing engine degrades a `mine` to file-level with a `WARN`, never a failure.

## Activity metrics

`prs` and `commits` read delivery activity over a date window — `--since`/
`--until`, defaulting to the last month — and report a repo **total** row first,
then a per-author breakdown:

```bash
devbot tool forensics prs ./core --since 2026-09-21 --until 2026-09-25
devbot tool forensics commits ./core --since 2026-09-21 --until 2026-09-25
```

- **`prs`** — pull requests **merged** in the window: count, median commits per PR, median lines changed per PR, median created→merged span, and PRs per calendar day. Grouped by PR author.
- **`commits`** — commits in the window: count, median lines changed per commit, and commits per calendar day. Grouped by author email, folded through the repository's `.mailmap`. The window is the author date; git walks history by committer date, so a commit authored inside the window but committed outside it can be omitted.

Both are also embedded in a `run` / `report --with-prs` document, so one file carries the delivery picture without a second command — commit activity whenever the store holds a bounded window (a report says so when it does not), PR activity when an authenticated `gh` is available.

PR data comes from a provider adapter under `sources/<name>/plugin.sh` (`meta | doctor | fetch`), so GitLab follows GitHub without touching the core; the shipped `sources/github` reads the authenticated `gh` CLI. `forensics sources doctor` reports whether each adapter's engine is ready. Fetched PRs are cached in a stable store at `<repo>/.forensics/prs.sqlite` — separate from the timestamped analysis store — and a request only reaches the provider for the spans of the window the cache does not already cover (`--refresh` forces a re-fetch).

## Method caveats

Churn/ownership attribution is approximate (`git blame` over current unit spans); defect origin uses a simplified SZZ heuristic. Both are reported as signals with their error modes, never as verdicts about people. True DORA metrics require deploy/incident data and are outside the git-only path.

Unit ownership and unit churn are **anchored at the window's end date**, not bound by its start: authorship is cumulative up to that instant, and a line written after it is not attributed. Static complexity has no time dimension at all — it is measured on the current tree, so complexity-ranked views (hotspots, priority) rank today's code against the window's change rate, not the code as it was.

Complexity is a decision-point count (1 + branches, cases and boolean operators) applied to each unit's own scope — nested functions, closures and lambdas are their own units and do not inflate the enclosing one. A class' complexity (WMC) sums its direct members (methods, accessors, constructors, initializer blocks); a `default:` clause counts, as does a `case`.

## See also

- [Architecture](/modules/agentic/architecture) — the boundaries coupling is judged against
- [Refactor](/modules/agentic/refactor) — the same core-plus-plugins pattern applied to writing
