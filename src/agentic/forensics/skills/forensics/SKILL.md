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

| Command                                                                                                                                                                                  | Purpose                                                                                                                                                                           |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `run [<repo>] [--since <date>] [--until <date>] [--out <dir\|file>] [--all] [--trends] [--defects <csv>] [--modules name=prefix,...]`                                                    | Mine and report in one step, writing a single self-contained Markdown file. The one-shot entry point.                                                                             |
| `mine [<repo>] [--since <date>] [--until <date>] [--db <path>] [--lang auto] [--granularity file\|unit] [--no-defects] [--trends] [--defects <csv>] [--modules name=prefix,...] [--all]` | Mine history + units + metrics + commit analysis into the SQLite store. Bounded to the last calendar month; `--all` mines the whole history.                                      |
| `analyse <db> [--view <view>] [--top N] [--format md\|json]`                                                                                                                             | Query one view.                                                                                                                                                                   |
| `report <db> [--out <dir\|file>] [--format md\|json\|html] [--with-prs] [--with-analysis]`                                                                                               | One document across every view, with a Data-quality block, commit activity and — with `--with-prs` — merged-PR activity. A `.md`/`.json`/`.html` `--out` path is the file itself. |
| `doctor [--project <dir>]`                                                                                                                                                               | Resolve each language plugin's engine.                                                                                                                                            |
| `langs`                                                                                                                                                                                  | List registered language plugins and capabilities.                                                                                                                                |
| `provision --lang <lang>`                                                                                                                                                                | Install a pinned engine into `storage/forensics/<lang>`.                                                                                                                          |
| `prs [<repo>] [--source github] [--since <date>] [--until <date>] [--refresh]`                                                                                                           | Merged PR metrics per author + repo total, served from the PR cache.                                                                                                              |
| `commits [<repo>] [--since <date>] [--until <date>]`                                                                                                                                     | Commit metrics per author + repo total, folded via `.mailmap`.                                                                                                                    |
| `sources`                                                                                                                                                                                | List registered provider adapters (e.g. github).                                                                                                                                  |

Views: `hotspots`, `priority`, `trends`, `change-rate`, `coupling`, `ownership`,
`concentration`, `unit-ownership`, `unit-concentration`, `commit-types`,
`authors`, `tickets`, `defects`, `defect-density`, `risk`, `time-to-fix`,
`fixers`, `process`, `releases`, `modules`, `architecture`, `structural`.

The default store is `<repo>/.forensics/<timestamp>.sqlite` (self-ignoring — it writes a `.gitignore` containing `*`).

## Reading the Output

- **Data quality first** — the block names every source the run could draw on, its count, and how to enable it when absent. A section reading `_(none)_` because its source was never supplied is not evidence of absence; check this block before drawing a conclusion, and restate its gaps in any write-up.
- **Hotspots** — high complexity × high change frequency; investigate before refactoring.
- **Temporal coupling** — units that change together without a structural dependency; a missing abstraction or an undocumented contract. Expected for a feature spanning layers; a concern when it crosses intended boundaries.
- **Ownership concentration** — knowledge held by one developer (bus-factor risk) or diffuse responsibility (many authors, no owner).
- **Commit-history intelligence** — conventional-commit mix overall and per author, defect origin (which commit/author introduced the bugs being fixed), and the time from defect to fix, boxed to the mining date range, with identities folded via `.mailmap`.
- **Activity metrics** — PRs merged and commits in a window, per author and as a repo total; the window defaults to the last month. Both are embedded in a `run` / `report --with-prs` document.

### Turning figures into recommendations

`report --with-analysis` (and `run`) reserve an `## Analysis & recommendations`
section for the agent's own reading. Fill it in — with figures, not adjectives:

- **Refactoring targets** — from Hotspots, Debt priority and Complexity trends. Name the file, the signal (complexity × change rate, complexity still growing) and the numbers, then order them. Say what makes each worth attention now.
- **Bus factor & knowledge sharing** — from Ownership, Ownership concentration, Unit ownership risk and the bus-factor line. Name the files and units that are single-owner, say whom the bus factor constrains, and propose the concrete mitigation (pairing, review rotation, secondary owners, documentation).
- **Limits** — restate every source the Data-quality block reports absent, so the reader knows what the analysis could not see.

Generic advice ("add more tests") is not analysis and must not appear.

## Method Caveats (MUST surface these when reporting)

- **Attribution is approximate.** Unit churn and ownership are derived from `git blame` over the _current_ unit line spans — historical spans are not reconstructed.
- **Every metric is window-bound, and ownership is anchored.** `mine` defaults to the last calendar month (`--all` lifts the bound and cannot be combined with `--since`/`--until`) and records the window in the store, so every view shares one time base within that store. Bounds take `YYYY-MM-DD` or ISO-8601 in UTC — a date-only value is that UTC day, not git's approximate `"last year"` forms. Unit ownership and churn are anchored at the window's **end** date, not restricted by its start — authorship is cumulative to that instant. Static complexity has no time dimension at all: hotspots and priority rank today's code against the window's change rate.
- **Two date bases, deliberately.** Mined history is selected on **committer** date (git's walk) and the dates the report prints are those committer dates, so every window-scoped figure agrees with the selection. The `commits` activity command keeps **author** dates instead — a rebased or backdated commit can appear in one and not the other. Release counts and release-cadence figures are window-scoped, not all-time.
- **Defect origin is a heuristic.** Inducing commits come from a simplified SZZ (blame of the lines a fix changed); it has known false positives and negatives. Treat it as a process signal, never as a verdict about a person.
- **Boundary coverage bounds the module views.** When `--modules` declares fewer prefixes than the tree has, the uncovered files are `(unassigned)` and cannot form a cross-module pair — the report states the coverage under Modules, so an empty cross-module coupling is read as "no attribution", not "no coupling".
- **Git-only DORA is a proxy.** Change-failure rate, time-to-fix and lead time are derived from commits; true DORA (deployment frequency, MTTR) needs deploy and incident data and is out of scope for the git-only path.
- **The PR cache is incremental.** `prs` fetches only the window spans the local cache lacks; a window ending "now" is never final, so its tail is refreshed on a later run (`--refresh` forces a full re-fetch). A report without an authenticated `gh` notes the PR section as unavailable rather than failing.
- **Commit windows filter on author date.** `commits` keeps commits whose author date is in the window; because git walks history by committer date, a commit authored inside the window but committed outside it can be omitted.

## See Also

- `devbot:forensics-report` — the command that runs this skill for a project and writes the analysis
- `devbot:architecture-rules` — the boundaries the coupling should be judged against
- `devbot:audit-codebase` — holistic consistency audit
- `devbot:make-adr` — record a boundary decision the analysis motivates
