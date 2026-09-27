---
title: "Forensics"
description: "Behavioral code analysis over version-control history — hotspots, temporal coupling, ownership, trends and commit-history intelligence, after Tornhill's Code as a Crime Scene."
skills: ["forensics"]
tools: ["forensics"]
---

Investigates how a codebase has _evolved_ rather than how it looks right now: it mines git history and per-language static metrics into a SQLite store, then reports where technical and organizational risk repeatedly appears.

```bash
devbot tool forensics mine <repo> --since "last year"
devbot tool forensics report .forensics/<timestamp>.sqlite --out ./forensics-report
```

`mine` writes the store; `analyse` queries one view; `report` renders every view
into one Markdown or JSON document.

## What it produces

- **Hotspots** — complexity × change rate, ranked; the refactoring priority list.
- **Debt priority** — a composite of change, complexity, coupling, defect rate and ownership risk, with every component exposed per file.
- **Complexity trends** — how a file's complexity grows across sampled revisions (`mine --trends`).
- **Change rate** — commits and commits-per-active-day per file.
- **Temporal coupling** — files that change together without a structural dependency.
- **Ownership & concentration** — authors per file and per unit, top-author share, bus factor.
- **Defects & risk** — SZZ defect origin, time-to-fix, external defect counts (`mine --defects <csv>`), and risk = hotspot × defects.
- **Commit-history intelligence** — conventional-commit mix (overall and per author), tickets, commit-process metrics and release cadence, boxed to a date range.
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

## Method caveats

Churn/ownership attribution is approximate (`git blame` over current unit spans); defect origin uses a simplified SZZ heuristic. Both are reported as signals with their error modes, never as verdicts about people. True DORA metrics require deploy/incident data and are outside the git-only path.

Complexity is a decision-point count (1 + branches, cases and boolean operators) applied to each unit's own scope — nested functions, closures and lambdas are their own units and do not inflate the enclosing one. A class' complexity (WMC) sums its direct members (methods, accessors, constructors, initializer blocks); a `default:` clause counts, as does a `case`.

## See also

- [Architecture](/modules/agentic/architecture) — the boundaries coupling is judged against
- [Refactor](/modules/agentic/refactor) — the same core-plus-plugins pattern applied to writing
