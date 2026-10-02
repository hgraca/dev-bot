---
name: devbot:memory-management
description: "Use when deciding where to save knowledge, formatting a memory entry, or auditing the vault."
---

# Memory Management — Vault Structure & Rules

Canonical reference for all `.agents/memory/` vault operations. Other memory skills reference this skill for structure, routing, and quality rules.

## When to Apply

- Deciding where to save knowledge
- Formatting memory entries
- Auditing vault structure or latent note quality
- When another memory skill references vault rules

## 1. Vault Structure

```
.agents/memory/
  active/                 <- always-on context (loaded like AGENTS.md)
  latent/
    PDRs/                    <- product decisions, stakeholder answers (one file per item)
    ADRs/                    <- architecture/technical decisions (one file per item)
    global/                  <- lessons reusable across projects (one file per item)
      <technology>/          <- see Section 2 for full bucket list and classification rules
    learnings/              <- lessons specific to this project (one file per item)
  work/
    active/                  <- in-progress work notes (3 issues max)
    archive/YYYY/MM/DD       <- completed work notes by year/month/day

  reference/                 <- architecture maps, flow docs, codebase knowledge
  thinking/                  <- scratchpad for drafts (promote or delete)
```

### Commit status (tracked vs local)

Folders differ in git status — by design, not an oversight:

- **Tracked** (committed when `commit_memory: true`): `active/`, `latent/ADRs/`, `latent/PDRs/`, `latent/learnings/`, `reference/`.
- **Local, gitignored** (never committed): `work/` (plans, backlogs, WIP), `thinking/` (scratch), and the `latent/global/` symlink — its target, `storage/global-memories/`, is tracked separately.

Work items (`work/active/<…>/backlog.md`, `work/archive/<…>`) and every `thinking/` note are **local artifacts**: never `git add` or commit them, and never ask the user where they live or whether to commit them — that is settled. An artifact that must survive across machines belongs in `reference/` or `latent/`.

Each `latent/` file is a standalone `.md` with YAML frontmatter (`date`, `keywords`, and optionally `see`, `aliases`, `supersedes`, `superseded_by`). Body starts after frontmatter — no metadata in body.

## 2. Routing Table

| Content                                         | Destination                                       |
| ----------------------------------------------- | ------------------------------------------------- |
| Agent bootstrap instructions (always-on)        | `active/`                                         |
| Product decision + rationale                    | `latent/PDRs/` (new file per item, see section 5) |
| Human stakeholder answer to project question    | `latent/PDRs/` (new file per item)                |
| New rule from stakeholder                       | `latent/PDRs/` (new file per item)                |
| Architecture or technical decision + rationale  | `latent/ADRs/` (new file per item)                |
| Lesson reusable across projects (tech-specific) | `latent/global/<technology>/` (new file per item) |
| Lesson specific to this project                 | `latent/learnings/` (new file per item)           |
| In-progress work note                           | `work/active/`                                    |
| Completed work note                             | `work/archive/YYYY/`                              |
| Architecture map or flow doc                    | `reference/`                                      |
| Draft or reasoning scratchpad                   | `thinking/` (promote or delete, see section 7)    |
| Partial-progress checkpoint                     | `thinking/YYYY-MM-DD-HH:MM:SS-<task>-partial.md`  |

**Routing rules:**

- Create a new file per item — never append to existing files
- File name: `YYYYMMDDHHMMSS-NN-<max-10-word-subject>.md` (timestamp = item date, NN = sequence within same second)
- Include YAML frontmatter: `date`, `keywords` (1–5 focused terms — tool names, concept names, domain terms)
- One entry per insight
- Include dates in entries

**global/ (cross-project) vs learnings/ (project-specific) decision rule:**

- `global/<tech>/` — lesson applies to the technology/tool regardless of project (e.g. a Docker gotcha, a Laravel pattern, a shell trick). Another project using the same tech would benefit.
- `learnings/` — lesson is specific to this project's domain, architecture, or conventions. Not useful elsewhere.
- **Specificity rule**: when content fits two buckets, the more specific wins (e.g. `laravel` beats `php`; `argocd` beats `k8s`; `kafka` beats `java`; `bun` beats `javascript`; `signoz` beats `otel`).
- **Classification signals** — match against filename + title + body (first match wins):

| Bucket            | Match when content mentions…                                                                |
| ----------------- | ------------------------------------------------------------------------------------------- |
| `devbot:qmd`      | qmd, XDG_CACHE_HOME, hybrid search, tobiqmd                                                 |
| `mdctx`           | mdctx, MDCTX_ROOT, context-index, memory_search_provider                                    |
| `devbot:graphify` | graphify, knowledge graph, god nodes                                                        |
| `promptfoo`       | promptfoo, eval assertion, rubric assertion                                                 |
| `pentagi`         | pentagi                                                                                     |
| `ogham`           | ogham                                                                                       |
| `obsidian`        | obsidian                                                                                    |
| `argocd`          | argocd, argoproj, sync-wave, ServerSideDiff                                                 |
| `istio`           | istio, VirtualService, istiod, envoy                                                        |
| `signoz`          | signoz                                                                                      |
| `otel`            | opentelemetry, otel demo, otel collector, otlp                                              |
| `kafka`           | kafka, rdkafka, PARTITION_EOF, consumer_group, KafkaQueue                                   |
| `helm`            | helm chart, helm upgrade, helm install, helm release                                        |
| `k8s`             | kubernetes, k8s, k3d, kubectl, StatefulSet, CronJob, ConfigMap, kustomize, klipper, inotify |
| `bun`             | bun test, bun esm, mock.module, bun run                                                     |
| `npm`             | npm install, npm ENOTEMPTY                                                                  |
| `uv`              | uv tool, uv install, uv upgrade                                                             |
| `mcp`             | mcp server, mcp tool, mcp client, mcp protocol, json-rpc, stdio transport, mcp-server-git   |
| `opencode`        | opencode, plugin api, plugin hook, opencode.jsonc, slash command, session.idle              |
| `devbot`          | devbot, issue folder, planning stage, memory vault, search-memory, remember-session         |
| `laravel`         | laravel, artisan, eloquent, workbench                                                       |
| `phpunit`         | phpunit, mockery, createMock, createStub, AllowMockObjects                                  |
| `php`             | php, symfony, composer, readonly class, set_error_handler                                   |
| `git`             | git commit, git apply, git stash, git blob, git hook, pre-commit hook, blob corruption      |
| `docker`          | docker, docker-compose, container, docker bridge                                            |
| `shell`           | bash, shell, makefile, posix, pipefail, set -e, heredoc, symlink                            |
| `javascript`      | javascript, typescript, node.js, esm, commonjs                                              |
| ...               | any other technology not listed here                                                        |

If no technology bucket fits, use `learnings/`.

## 3. Retrieval Rules

- active/ loads automatically at session start — do not re-read
- latent/ files: use `search-memories` for all categories — do NOT read entire folders
  - `search-memories` searches the CURRENT project vault + the shared global store under whichever engine `memory_search_provider` selects (qmd or mdctx); it returns file content with frontmatter stripped (data only)
  - Read specific files directly only when you know the exact filename
- **Memory search MUST go through `search-memories`** (devbot-tools MCP tool or CLI): it always scopes to the CURRENT project vault + global store and nothing else. Raw engine-native tools (qmd MCP/CLI, mdctx MCP) can span other stores/roots or miss the current project's. Both engines are keyword-only (BM25) — there is no semantic route to reach for.
- All other files: search before read; max 3 non-latent notes per task; discard results with relevance score < 0.6
- If `search-memories` returns no matches, the index may not be built yet or a reindex may still be in progress — do not loop reindex → search → reindex. Check `reindex-memories status`; if `in_progress`, wait and re-search once. Repeated reindex calls coalesce into one job.

## 4. Writing Constraints

- **Deduplication check before writing**: Before writing a new latent file, query existing memories using `search-memories` with 2–3 representative keywords from the finding. If an entry already covers the same learning (same topic + same conclusion), skip it — do not create a duplicate.
- When a PDR has a related ADR (or vice versa), add the related file's path to the `see` frontmatter array in **both** files. Example: a PDR defining a product rule and an ADR specifying how to implement it should each list the other in their `see` arrays.
- **Supersession is bidirectional**: when a newer note replaces an older one, set `supersedes:` on the newer note **and** `superseded_by:` plus a reader-visible body banner on the older note. The older note is the one a search hit lands on, so its warning must live in the body (frontmatter is stripped from `search-memories` output). Full format in §6 "Supersession and aliases".
- Never write: secrets, API keys, passwords
- Never write: files in vault root (only subfolders)
- Never write: agent instructions outside `active/` expecting auto-load

## 5. Latent Note Quality Criteria

| Folder          | Good entry has                                                   |
| --------------- | ---------------------------------------------------------------- |
| `PDRs/`         | Decision + rationale (not just decision)                         |
| `ADRs/`         | Decision + rationale (not just decision)                         |
| `global/<tech>` | Reusable across projects; tech-specific; actionable with context |
| `learnings/`    | Project-specific; includes domain/architecture context           |

## 6. Latent Item File Format

All latent items are standalone `.md` files. File naming: `YYYYMMDDHHMMSS-<slug>.md`

- Timestamp: date of the item (`HHMMSS` = `000000` when only date known)
- Slug: max 10 words, hyphen-separated, lowercase, no special chars

### ADRs/ and PDRs/ — `keywords` frontmatter, single `##` body

Location: `latent/ADRs/` or `latent/PDRs/` inside the project vault.

```markdown
---
date: YYYY-MM-DD
keywords: ["keyword1", "keyword2"]
aliases: ["synonym", "alternate name"]
see: ["PDRs/YYYYMMDDHHMMSS-related-decision.md", "ADRs/YYYYMMDDHHMMSS-related-adr.md"]
supersedes: ["PDRs/YYYYMMDDHHMMSS-older-decision.md"]
superseded_by: ["ADRs/YYYYMMDDHHMMSS-newer-decision.md"]
---

## <Decision title>

> **Superseded by** `ADRs/YYYYMMDDHHMMSS-newer-decision.md` (YYYY-MM-DD).

<One-paragraph description of the decision, what changed, why, and any constraints or caveats.>
```

- `keywords`: 1–5 focused terms (tool names, concept names, domain terms). Always include the primary tools/domain as first keyword.
- `aliases`: optional array of 1–5 synonyms, alternate names, or in-vault coinages that do not appear verbatim in the note — the words a future search might use instead (see §6 "Supersession and aliases").
- `see`: optional array of paths relative to the `latent/` root pointing to related latent memories. Use to cross-link a PDR with the ADR that implements it, or an ADR with the PDR that motivated it. Omit the key when there are no related memories.
- `supersedes` / `superseded_by`: optional bidirectional pointers set when one memory replaces another — see §6 "Supersession and aliases".
- Body: single `##` heading + one prose paragraph. No sub-sections. On a superseded note the banner is the first line after the heading.

### global/<tech>/ — `keywords` frontmatter, single `##` body

Location: `storage/global-memories/<tech>/` (the shipped, tracked global knowledge base; accessed via the `latent/global/<tech>/` symlink in each project vault). Use for lessons reusable across projects — the tech bucket determines the subfolder (see section 2 classification table).

```markdown
---
date: YYYY-MM-DD
keywords: ["<tech>", "keyword2"]
aliases: ["synonym", "alternate name"]
trigger-on: ["<pattern-id-1>", "<pattern-id-2>"]
supersedes: ["<tech>/YYYYMMDDHHMMSS-older-note.md"]
superseded_by: ["<tech>/YYYYMMDDHHMMSS-newer-note.md"]
---

## <Title>

> **Superseded by** `<tech>/YYYYMMDDHHMMSS-newer-note.md` (YYYY-MM-DD).

<One-paragraph description of the lesson — what the trap/pattern/rule is, why it matters, and how to apply or avoid it. Self-contained: no references to other files needed to act on this.>
```

- `keywords`: first keyword MUST be the bucket name (e.g. `"bun"`, `"argocd"`). 1–5 terms total.
- `aliases`: optional array of 1–5 synonyms, alternate names, or coinages that do not appear verbatim in the note — the words a future search might use instead.
- `trigger-on`: optional array of technology/pattern identifiers (NOT file paths — paths vary across projects). Use when the note describes a gotcha that should auto-surface during implementation whenever a task touches that technology. Identifiers should be stable pattern names: e.g. `"php-fpm-env-config"`, `"dockerfile-multi-stage"`, `"composer-allow-plugins"`. The orchestrator's `devbot:implement-story` Step 0 surface-keyword search matches these against the task's implementation surface keywords. See `devbot:implement-story` SKILL Step 0 for the matching procedure.
- `supersedes` / `superseded_by`: optional bidirectional pointers set when one memory replaces another — see §6 "Supersession and aliases". Paths are relative to this store's root (`storage/global-memories/`).
- Body: single `##` heading + one prose paragraph. No sub-sections. On a superseded note the banner is the first line after the heading.
- **Do not** add `[[wikilinks]]` — global files are shared across projects and cannot reference project-specific notes.

### learnings/ — `keywords` frontmatter, `#` title, multiple `##` sections

Location: `latent/learnings/` inside the project vault. Use for lessons specific to this project's domain, architecture, or conventions.

```markdown
---
date: YYYY-MM-DD
keywords: ["keyword1", "keyword2"]
aliases: ["synonym", "alternate name"]
supersedes: ["learnings/YYYYMMDDHHMMSS-older-lesson.md"]
superseded_by: ["learnings/YYYYMMDDHHMMSS-newer-lesson.md"]
---

# <Title>

> **Superseded by** `learnings/YYYYMMDDHHMMSS-newer-lesson.md` (YYYY-MM-DD).

<Body. Use multiple ## sections as needed. Be specific and actionable.>
```

- `keywords`: 1–5 focused terms (tool names, concept names, domain terms). Always include the primary tools/domain as first keyword.
- `aliases`: optional array of 1–5 synonyms, alternate names, or coinages that do not appear verbatim in the note — the words a future search might use instead.
- `supersedes` / `superseded_by`: optional bidirectional pointers set when one memory replaces another — see §6 "Supersession and aliases".
- Body: `#` title, then multiple `##` sections as needed. On a superseded note the banner is the first line after the title.

### Supersession and aliases (all latent formats)

**Supersession** — when a newer memory replaces an older one, link both directions and warn the reader:

- On the **newer** note: `supersedes: ["<old path, relative to the store root>"]`.
- On the **older** note: `superseded_by: ["<new path, relative to the store root>"]`.
- On the **older** note, the first line of the body (immediately after the title heading) is a blockquote banner:
  - full replacement: `> **Superseded by** <new path> (YYYY-MM-DD).`
  - partial reversal: `> **Superseded in part by** <new path> (YYYY-MM-DD) — <what no longer holds>.`
- The banner is load-bearing: `search-memories` strips frontmatter from everything it returns, so a `superseded_by:` key alone is invisible to the reader. The key exists for tooling and cross-reference integrity; the banner is what a human or agent actually sees.
- For a cross-store link (a project note superseding a global note, or vice versa) use the path as it resolves from the referencing note's own store root.

**Aliases** — `aliases:` is an optional array of 1–5 synonyms, alternate names, or in-vault coinages that do **not** appear verbatim in the note: the words a future search might use instead. Both memory engines are keyword/BM25 only, so a note is found only by words it (or its frontmatter) contains; `aliases` widens that surface.

### Entry quality rules (all formats)

- **Specific, not generic** — "Always pass `--no-interaction` to Artisan" not "Be careful with CLI commands"
- **Self-contained** — future agents need to understand _why_ without reading other files
- **No scaffolding** — no `- **Date**: ...`, `- **Status**: ACTIVE`, `- **Scope**: ...` lines in body

### Pruning (when global/<tech>/ or learnings/ exceeds 100 files)

- Mark entries as `SUPERSEDED` — `superseded_by:` frontmatter plus the body banner (see "Supersession and aliases" above) — when a newer entry replaces them
- Delete superseded files after one more session
- Review files older than 6 months for continued relevance
- Only orchestrator or human stakeholder may remove files

## 7. Thinking/ Lifecycle

### Promote or discard

For each file in `thinking/`:

- Contains reusable lesson -> promote to latent/, then **delete**
- Completed work -> **delete**
- Still live WIP -> keep; rename to `partial-<task>-YYYY-MM-DD.md` if not descriptive

### Hygiene

- Flag any `thinking/` file older than 7 days for user review
- Partial-progress notes use: `YYYY-MM-DD-HH:MM:SS-<task>-partial.md`

## 8. Wrap-Up (on "wrap up" / "wrapping up")

1. Promote session learnings to appropriate `latent/global/<tech>/` or `latent/learnings/` folder (new file per item)
2. Archive completed `work/active/` notes -> `work/archive/YYYY/`
3. Tell user what was promoted and saved

## 9. Memory Tiers (reference)

| Tier             | Store           | Content                                                      | Writer                                        |
| ---------------- | --------------- | ------------------------------------------------------------ | --------------------------------------------- |
| Long term active | active/ notes   | Active memories, always loaded                               | Human                                         |
| Long-term latent | latent/ notes   | Architectural decisions, domain knowledge, patterns, gotchas | Agent at wrap-up, human for strategy          |
| Temporary        | thinking/ notes | temporary files                                              | Agent when it needs a temporary file location |
