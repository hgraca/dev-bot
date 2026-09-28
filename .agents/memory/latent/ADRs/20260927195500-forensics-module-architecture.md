---
date: 2026-09-27
keywords: ["forensics", "module", "architecture", "plugins", "hotspots", "tornhill"]
see: []
---

## Forensics module architecture (Tornhill code forensics as a dev-bot module)

`src/agentic/forensics` rebuilds `hgraca/php-phorensic` as a dev-bot agentic module: it mines a repository's git history and per-language static metrics into SQLite, then reports hotspots, temporal coupling, ownership, trends, architecture alignment, commit-history intelligence and delivery-activity metrics. The decisions below are the ones future work must preserve.

**AD-1 — language-agnostic core, language-specific plugins.** `tools/forensics.sh` + `lib/forensics-lib.py` own git mining, storage, analysis and reporting; nothing language-specific lives there. Every language is one `langs/<lang>/` directory.

**AD-2 — plugin contract `meta | doctor | provision | units`.** `units` reads `{"project","files"}` on stdin and emits `{"ok","units":[{path,name,kind,start_line,end_line,complexity,loc,parent}],"errors"}`. The core honours `ok:false` and per-file `errors` as warnings; a failing engine degrades to file-level, never fails a mine.

**AD-3 — bash CLI + Python core.** A deliberate deviation from the `.ts`-authoritative rule (mirroring `refactor`): it uses stdlib `sqlite3` and keeps a human-facing CLI free of a `bun` runtime dependency.

**AD-4 — SQLite store at `<repo>/.forensics/<ts>.sqlite`** (self-ignoring). `meta.schema_version` is written on init and checked by `analyse`/`report`, which reject an incompatible store with an `ERROR:` instead of a traceback. JSON/CSV are export formats.

**AD-5 — approximate attribution, disclosed.** Unit churn and ownership derive from `git blame` over _current_ unit spans; historical spans are not reconstructed. Stated in the report's methodology footer.

**AD-6 — plugin-declared granularity.** A plugin reports units at the level its engine supports; the core falls back to file-level when a plugin reports none.

**AD-7 — normalized scores.** Hotspot/priority components are percentile-ranked (ties share a rank, computed as the count of strictly-smaller values) and combined as a transparent weighted sum, not a raw product.

**AD-8 — simplified SZZ.** Defect origin blames the pre-fix lines at the fix's parent revision (`core.quotePath=false`, old path so renames/deletions resolve). A heuristic with known errors, reported as a process signal — never a verdict about a person.

**AD-9 — self-ignoring output dir.** The `*` `.gitignore` is written only inside `.forensics/`; an explicit `--db` elsewhere is never given a blanket ignore.

**Plain CLI, not an MCP tool.** Same posture as `refactor`: the `devbot:forensics` skill documents it and an agent runs it via `devbot tool forensics …`.

**Unit identity.** `(path, kind, name)`; a language plugin disambiguates overloads in `name` (Java appends parameter types; TypeScript suffixes accessors `(get)`/`(set)`).

**Complexity scope.** A unit's complexity is a decision-point count (1 + branches, cases, boolean operators) over its own scope; nested functions, closures and lambdas are their own units and do not inflate the enclosing one. A class' complexity (WMC) sums its direct members. `default:` counts, as does `case`.

Shipped languages: `php` (PDepend), `ts` (TypeScript compiler API), `java` (JDK compiler tree API), `go` (stdlib `go/ast`). Adding another is a single directory answering the same four verbs.

**AD-A — provider source adapters, mirroring the language plugins.** Pull-request data comes from `sources/<name>/plugin.sh`, discovered by directory presence like `langs/`, answering `meta | doctor | fetch`. `fetch` reads `{"project","since","until"}` on stdin and emits `{"ok","pull_requests":[…],"errors"}`. GitHub ships first; GitLab is one more directory. Only a `github.com` origin is accepted, and `fetch` confirms the repository is visible, so a wrong or unreachable repository fails loudly instead of caching an empty window.

**AD-B — a dedicated stable PR cache.** Remote PRs persist in `<repo>/.forensics/prs.sqlite` (own `schema_version`), never in the timestamped analysis store — that store is reset on every `mine`, so a cumulative cache cannot live in it. Tables are provider-agnostic, keyed `(source, repo, number)`.

**AD-C — interval-coverage cache.** `pr_coverage` records fetched windows; a request subtracts the covered intervals from `[since, until]` and fetches only the gaps, so a repeat run makes no remote call. `--refresh` forces a full-window fetch. A window ending "now" is never final, so its tail is refetched naturally by the gap maths.

**AD-D — commits stay git-only, folded by `.mailmap`.** `commits` reads git directly (no cache), grouping authors by email folded through the repository's `.mailmap` (git `%aN`/`%aE`). The window is the author date; because git walks history by committer date, a commit authored in-window but committed outside it can be omitted.

**AD-E — GitHub via one paginated GraphQL search.** `gh api graphql` returns `commits.totalCount`, additions, deletions and changed files for every merged PR in the window in one query — no per-PR call. No token handling: the machine's authenticated `gh` is used. The adapter never writes to GitHub.

**AD-F — pure maths in `lib/metrics.py`.** Window resolution, medians, calendar-day frequency and interval coalescing/subtraction live in one unit-tested module; the CLI only orchestrates.
