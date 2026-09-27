---
title: "Forensics"
description: "Behavioral code analysis over version-control history — hotspots, temporal coupling, ownership, trends and commit-history intelligence, after Tornhill's Code as a Crime Scene."
skills: ["forensics"]
tools: ["forensics"]
---

Investigates how a codebase has _evolved_ rather than how it looks right now: it mines git history and per-language static metrics into a SQLite store, then reports where technical and organizational risk repeatedly appears.

```bash
devbot tool forensics mine <repo> --since "last year"
```

Phase 0 mines history + units + per-language metrics into the store; the analysis
commands (`analyse`, `report`) arrive in Phase 1.

## What it produces

- **Hotspots** — complexity × change rate, ranked; the refactoring priority list.
- **Temporal coupling** — units that change together without a structural dependency.
- **Ownership** — authors per unit/file, concentration, bus factor, orphaned code.
- **Trends** — complexity and churn over time.
- **Commit-history intelligence** — conventional-commit mix (overall and per author), defect origin (SZZ), and time-to-fix distributions, boxed to a date range.
- **Debt interest-rate priority** — a composite score across the signals above.

## Architecture

A language-agnostic core (`tools/forensics.sh` + `lib/forensics-lib.py`) owns git mining, storage, analysis and reporting. Language specifics live behind `langs/<lang>/plugin.sh`, which answers a four-verb contract:

| verb        | purpose                                                                       |
| ----------- | ----------------------------------------------------------------------------- |
| `meta`      | declare `lang`, `extensions`, `capabilities`, `unit_kinds`, `metrics`         |
| `doctor`    | report the resolved engine (project copy → scratch install) + container image |
| `provision` | install a pinned engine into `storage/forensics/<lang>`                       |
| `units`     | emit code units + static complexity as canonical JSON                         |

Adding a language is one `langs/<lang>/` directory — `php` (PDepend) ships first, `py`/`ts`/`rust` follow.

## Method caveats

Churn/ownership attribution is approximate (`git blame` over current unit spans); defect origin uses a simplified SZZ heuristic. Both are reported as signals with their error modes, never as verdicts about people. True DORA metrics require deploy/incident data and are outside the git-only path.

## See also

- [Architecture](/modules/agentic/architecture) — the boundaries coupling is judged against
- [Refactor](/modules/agentic/refactor) — the same core-plus-plugins pattern applied to writing
