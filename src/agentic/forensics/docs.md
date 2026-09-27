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
- **Change rate** — commits and commits-per-active-day per file.
- **Temporal coupling** — files that change together without a structural dependency.
- **Ownership & concentration** — authors per file, top-author share, bus factor.
- **Commit-history intelligence** — conventional-commit mix (overall and per author), tickets, defect origin (SZZ), and time-to-fix distributions, boxed to a date range.
- _Phase 2:_ complexity trends over time, architecture-vs-organization, and the composite debt interest-rate priority.

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
