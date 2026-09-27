---
name: devbot:forensics
description: "Use when analysing a codebase's evolution rather than its snapshot — hotspots, temporal coupling, ownership, trends, and commit-history intelligence — before a refactor or architecture review. Triggers on 'hotspots', 'temporal coupling', 'code forensics', 'who owns this code', 'refactoring priority'."
---

# Skill: Forensics

Behavioral code analysis over version-control history, after Adam Tornhill's _Your Code as a Crime Scene_. It mines how the system evolved, how developers interact with it, and where technical and organizational risk repeatedly appears — evidence a static snapshot cannot show.

## When to Apply

- Prioritizing refactoring: which code deserves attention before touching anything.
- Reviewing architecture: whether module/team boundaries match actual change patterns.
- Assessing knowledge risk: bus factor, concentrated ownership, orphaned code.
- Reading delivery process: conventional-commit mix, defect origin, time-to-fix.

## How to Run

The tool is a plain CLI — a human runs it directly, an agent runs it through bash:

```bash
devbot tool forensics <command> [options]
```

| Command                                                                                                                 | Purpose                                                                 |
| ----------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| `mine [<repo>] [--since <date>] [--until <date>] [--db <path>] [--lang auto] [--granularity file\|unit] [--no-defects]` | Mine history + units + metrics + commit analysis into the SQLite store. |
| `analyse <db> [--view <view>] [--top N] [--format md\|json]`                                                            | Query one view.                                                         |
| `report <db> [--out <dir>] [--format md\|json]`                                                                         | Full report across every view, with a methodology footer.               |
| `doctor [--project <dir>]`                                                                                              | Resolve each language plugin's engine.                                  |
| `langs`                                                                                                                 | List registered language plugins and capabilities.                      |
| `provision --lang <lang>`                                                                                               | Install a pinned engine into `storage/forensics/<lang>`.                |

Views: `hotspots`, `change-rate`, `coupling`, `ownership`, `concentration`,
`commit-types`, `authors`, `tickets`, `defects`, `time-to-fix`, `fixers`.
(`trends` and `architecture` arrive in Phase 2.)

The default store is `<repo>/.forensics/<timestamp>.sqlite` (self-ignoring — it writes a `.gitignore` containing `*`).

## Reading the Output

- **Hotspots** — high complexity × high change frequency; investigate before refactoring.
- **Temporal coupling** — units that change together without a structural dependency; a missing abstraction or an undocumented contract. Expected for a feature spanning layers; a concern when it crosses intended boundaries.
- **Ownership concentration** — knowledge held by one developer (bus-factor risk) or diffuse responsibility (many authors, no owner).
- **Commit-history intelligence** — conventional-commit mix overall and per author, defect origin (which commit/author introduced the bugs being fixed), and the time from defect to fix, boxed to the mining date range.

## Method Caveats (MUST surface these when reporting)

- **Attribution is approximate.** Unit churn and ownership are derived from `git blame` over the _current_ unit line spans — historical spans are not reconstructed.
- **Defect origin is a heuristic.** Inducing commits come from a simplified SZZ (blame of the lines a fix changed); it has known false positives and negatives. Treat it as a process signal, never as a verdict about a person.
- **Git-only DORA is a proxy.** Change-failure rate, time-to-fix and lead time are derived from commits; true DORA (deployment frequency, MTTR) needs deploy and incident data and is out of scope for the git-only path.

## See Also

- `devbot:architecture-rules` — the boundaries the coupling should be judged against
- `devbot:audit-codebase` — holistic consistency audit
- `devbot:make-adr` — record a boundary decision the analysis motivates
