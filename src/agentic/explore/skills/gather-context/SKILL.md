---
name: devbot:gather-context
description: "Use when the scout agent primes context about a topic or project area at session start."
---

# Gather Context

Use at session start to collect targeted context for the orchestrator before work begins.

## When to Apply

- Orchestrator delegates context-gathering for a topic or set of keywords.
- Session starts and orchestrator needs primed context before planning or delegating.

## Procedure

### 0. Load the scoped project's memory, then ensure its description

Load the always-on memory of the project this assignment is scoped to — the child
in a monorepo session, otherwise the session project — before any other read or
edit in it:

```bash
devbot tool project-memory "<a path inside the project>"
```

It prints that project's `AGENTS.md` and/or `CLAUDE.md` plus its
`<devbot_dir>/memory/active/**/*.md`, scoped to the project; report what it
returned under its own heading. The `devbot_dir` is the scoped project's own —
never assume `.agents`. In a normal session the harness has already loaded the
session project's active memory, so the command matters for a child.

Then check whether that same project's `<devbot_dir>/memory/active/project.md`
exists. If it does **not** exist, follow the `devbot:create-project-report` skill
to generate it before continuing. If it exists, proceed to the next step.

### 1. Parse the delegation prompt

The orchestrator's delegation prompt contains two distinct sections:

- **Keywords**: 1 or 2 words each (hyphenated compounds like `devbot:codebase-index` count as one word). These are search tokens — use them as-is for memory search, graphify, and codebase-engine queries. Do not split or rephrase them.
- **What I need to understand**: Sentences or questions that direct what to investigate. The report should answer these — they shape the focus of findings and the Summary section.

If neither section was provided, ask for both before proceeding.

### 1a. Monorepo sessions — one scout per touched project

When the session runs in a `monorepo` project (`.devbot.project.jsonc` has
`monorepo: true`), the primary agent predicts which managed projects the
request will touch and dispatches **one @scout assignment per predicted
project, in parallel**. Scout never delegates, so the fan-out is the primary
agent's job — this skill describes what each per-project scout does.

A scout scoped to a project passes that project as the memory focus, so its
search covers the project + the monorepo + the global store + configured
custom collections:

```bash
search-memories --query "<keyword>" --focus "<a path inside the project>"
```

Step 0 loads the child's memory before anything else in the child. Also resolve
the child's own `commit_memory` and `workflow` from its `.devbot.project.jsonc`
(project-first, global-fallback) and state them in the report, so downstream
writes commit in the right place and the work follows the workflow the child
selected. The scout's report does not stand in for the orchestrator loading that
same memory before its first read or edit in the child. Every report still lands in the
**monorepo's** `memory/thinking/`.

### 2. Gather memories

Use the `search-memories` tool to query memories using the identified keywords.

Id you do NOT have the `search-memories` tool available, use the bash fallback:

```bash
bash devbot tool search-memories \
  --format markdown \
  --collection <current-project> \
  --max-results 5 \
  --query "<keyword1>" \
  --query "<keyword2>"
```

If the bash script fails, use `glob` and `grep` to find files directly:

- `glob("glob_pattern")` to list files
- `grep("keyword_pattern")` to find content

If the search returns nothing, do not loop reindex → search → reindex. The index may still be building: check `reindex-memories status`; if `in_progress`, wait and re-run the search once. Repeated reindex calls coalesce — they don't make results appear faster.

### 3. Gather a git status report

Use the `git-report` tool to get a git status report.

Id you do NOT have the `git-report` tool available, use the bash fallback:

```bash
bash devbot tool git-report --format markdown
```

### 4. Gather sibling projects (only when the task may cross repositories)

Skip this step for a repository-local question — a 27-project roster adds noise, not context. Use the
`list-projects` tool only when the delegation mentions another service, a cross-repo change, or an
unknown sibling, and pass `--filter`/`--only` when the relevant names are already known.

If you do NOT have the `list-projects` tool available, use the bash fallback:

```bash
bash devbot tool list-projects
```

### 5. Gather codebase relationships knowledge (code-related topics only, and only when indexed)

Use the `graphify` MCP tools only when the topic is code-related **and** the graph is populated. Call
`graphify_graph_stats` first. A `graphify: not_ready (building)` result means the graph is being
built on MCP start: wait briefly and retry once. `not_ready (disabled)` or `not_ready (failed)`
means skip graph queries and write the reason in the report. Do not query an empty graph.

If you do NOT have the `graphify` MCP tools available, use glob + grep as fallback:

- `glob("**/*.md")` to list relevant documentation files
- `grep("keyword")` to find related content

### 6. Gather codebase patterns and architecture context (code-related topics only)

Use the project's active codebase engine. Consult the `devbot:codebase-index` skill — the shared slot that documents whichever engine `codebase_index_provider` selects (`codebase-memory` by default, `codebase-index` otherwise) — and use the MCP tools it names. If the engine is unavailable, says the project is not indexed, or reports the index as stale, record that in one line and fall back to grep/read; do not retry the same call.

If those MCP tools are not available, use glob + grep as fallback:

- `glob("src/**/*.{ts,js,php}")` to find source files matching the topic
- `grep("relevant_pattern")` to find patterns in the codebase
- `read(filePath)` to read key files

### 7. Gather directory structure (if topic is code-related or structural)

Use the `tree` tool to gather codebase patterns and architecture context.

If you do NOT have the `tree` tool available, use the bash fallback:

```bash
bash tree my/path/one my/other/path
```

### 8. Look up the task's Jira ticket (only when the atlassian MCP is live)

Two switches must both be on, and neither is assumed:

```bash
devbot tool project-for-path <project> --key modules                    # absence => enabled
devbot tool project-for-path <project> --key mcps [--session-root DIR]  # server map
```

Both on means `mcps` maps `atlassian` to `enabled` — another enabled server does
not count. When `atlassian` is absent or `disabled`, skip this step and say so in
one line. In a monorepo session pass the workspace root as `--session-root`,
the checkout the harness runs in.

With the entry `enabled`, load `devbot:atlassian` and search once with JQL built from the
delegation keywords — an issue key present in the request, otherwise one
`text ~ "<keyword>"` term per keyword, `AND`-ed, ordered by `updated DESC` and
filtered to exclude Done and Canceled. Request only the fields you report. In a
monorepo session every project's scout runs its own search, in parallel.

Read-only: never create, edit or transition an issue — that belongs to the
primary agent's ticket resolution (`devbot:jira-workflow`).

Report the best match, or several when they are genuinely plausible:

```text
PROJ-123 — <summary> — https://<site>.atlassian.net/browse/PROJ-123
```

When nothing matches, say `No matching Jira ticket` and name the JQL you ran.
Ten Rovo credits per natural-language search is the reason this is JQL, not the
semantic `search` tool.

### 9. Search Notion for related context (only when the notion MCP is live)

Two switches must both be on, and neither is assumed:

```bash
devbot tool project-for-path <project> --key modules                    # absence => enabled
devbot tool project-for-path <project> --key mcps [--session-root DIR]  # server map
```

The lookup runs only when the `modules` map does not disable `notion` **and**
`mcps` maps `notion` to `enabled`. Another enabled server does not count. When
the module is disabled, or `notion` is absent or `disabled` from `mcps`, skip
this step and say so in one line. In a monorepo session pass the workspace
root as `--session-root`, the checkout the harness runs in.

With both switches on, load `devbot:notion` and discover the search tool the
connection exposes: `notion-get-tool-access` lists the callable tools. Search
with `notion-search` and the delegation keywords joined into a short query — up
to 50 results. When `notion-connector-search` is also listed, call it alongside
the first search for connected sources (Slack, Drive, …); when `notion-search`
is absent, use the connector as the fallback; when both `notion-search` and
`notion-connector-search` are absent, call the legacy `notion-ai-search` by
name.
Run one search per keyword only when the keywords name clearly distinct
concepts and the joined search returns nothing; never fan out further. Open a
result with `notion-fetch` only when its title or snippet is plausibly relevant.
When none of the three is exposed, report `Notion search unavailable` and carry
on without Notion context.

Read-only: never create, update, comment on, move or delete a page or database —
this step gathers context, it does not edit the workspace. In a monorepo
session every project's scout runs its own search, in parallel.

Report the best matches with their links, or several when they are genuinely
plausible:

```text
<page title> — https://www.notion.so/<page-id>
```

When nothing matches, say `No matching Notion content` and name the query you
ran.

### 10. Compile context report

Produce structured Markdown report with sections:

```markdown
# Context Report

**Keywords**: <keyword-list>

## Memories

<!-- output body of `search-memories` tool -->

## Git status

<!-- output of `git-report` tool -->

## Jira ticket

<!-- the matching issue as `PROJ-123 — summary — URL`, or `No matching Jira ticket`; omit when the atlassian MCP is off -->

## Notion

<!-- the matching pages as `<title> — <url>`, `No matching Notion content`, or `Notion search unavailable` when enabled but no search tool is exposed; omit when the notion module is disabled or the notion MCP is off -->

## Sibling projects

<!-- output of the `list-projects` tool -->

## Graphify insights

<!-- report of the `devbot:graphify` insights — omit if not code-related -->

## Codebase insights

<!-- insights from the active codebase engine (see the `devbot:codebase-index` skill) — omit if not code-related -->

## Directory Structure

<!-- output of  the `tree` tool — omit if neither code-related nor structural -->

## Summary

<!-- 2-4 sentences: what is known, what is missing, recommended follow-up research -->
```

### 11. Store report to file

Write the compiled report to a file in `.../memory/thinking/` with the naming convention:

```
YYYYMMDDHHMMSS-<keyword-list>.md
```

Where:

- `YYYYMMDDHHMMSS` is the current UTC timestamp
- `<keyword-list>` is the keyword list joined by hyphens (e.g. `auth-jwt-login`)

Example: `20260518143000-auth-jwt-login.md`

### 12. Signal completion

Before signaling completion, verify that the report file has in fact been written to disk, using `ls ...`.

Signal `[FINISHED]` per `devbot:agent-communication` skill.
Include in the signal:

- The **absolute path** of the report file written to `thinking/`.
- A brief summary (3–5 bullets) of the key findings.

The orchestrator will read the full report from disk and display it to the user.
