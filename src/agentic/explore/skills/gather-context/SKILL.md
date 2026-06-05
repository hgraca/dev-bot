---
name: gather-context
description: "Gather session context for the orchestrator at session start. Use this skill whenever the scout agent is activated to prime context about a topic or project area."
---

# Gather Context

Use at session start to collect targeted context for the orchestrator before work begins.

## When to Apply

- Orchestrator delegates context-gathering for a topic or set of keywords.
- Session starts and orchestrator needs primed context before planning or delegating.

## Procedure

### 1. Parse the delegation prompt

The orchestrator's delegation prompt contains two distinct sections:

- **Keywords**: 1 or 2 words each (hyphenated compounds like `codebase-index` count as one word). These are search tokens — use them as-is for memory search, graphify, and codebase-index queries. Do not split or rephrase them.
- **What I need to understand**: Sentences or questions that direct what to investigate. The report should answer these — they shape the focus of findings and the Summary section.

If neither section was provided, ask for both before proceeding.

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

### 4. Gather sibling projects

Use the `list-projects` tool to list the sibling projects configured in the global devbot config — each with its name, full path, and whether the agent has access to it.

If you do NOT have the `list-projects` tool available, use the bash fallback:

```bash
bash devbot tool list-projects
```

### 5. Gather codebase relationships knowledge (if topic is code-related)

Use the `graphify` MCP tools with the identified keywords to get a graphify report.

If you do NOT have the `graphify` MCP tools available, use glob + grep as fallback:

- `glob("**/*.md")` to list relevant documentation files
- `grep("keyword")` to find related content

### 6. Gather codebase patterns and architecture context (if topic is code-related)

Use the `codebase-index` MCP tools to gather codebase patterns and architecture context.

If you do NOT have the `codebase-index` MCP tools available, use glob + grep as fallback:

- `glob("src/**/*.{ts,js,php}")` to find source files matching the topic
- `grep("relevant_pattern")` to find patterns in the codebase
- `read(filePath)` to read key files

### 7. Gather directory structure (if topic is code-related or structural)

Use the `tree` tool to gather codebase patterns and architecture context.

If you do NOT have the `tree` tool available, use the bash fallback:

```bash
bash tree my/path/one my/other/path
```

### 8. Compile context report

Produce structured Markdown report with sections:

```markdown
# Context Report

**Keywords**: <keyword-list>

## Memories

<!-- output body of `search-memories` tool -->

## Git status

<!-- output of `git-report` tool -->

## Sibling projects

<!-- output of the `list-projects` tool -->

## Graphify insights

<!-- report of the `graphify` insights — omit if not code-related -->

## Codebase-index insights

<!-- insights of the `codebase-index` — omit if not code-related -->

## Directory Structure

<!-- output of  the `tree` tool — omit if neither code-related nor structural -->

## Summary

<!-- 2-4 sentences: what is known, what is missing, recommended follow-up research -->
```

### 9. Store report to file

Write the compiled report to a file in `.../memory/thinking/` with the naming convention:

```
YYYYMMDDHHMMSS-<keyword-list>.md
```

Where:

- `YYYYMMDDHHMMSS` is the current UTC timestamp
- `<keyword-list>` is the keyword list joined by hyphens (e.g. `auth-jwt-login`)

Example: `20260518143000-auth-jwt-login.md`

### 10. Signal completion

Before signaling completion, verify that the report file has in fact been written to disk, using `ls ...`.

Signal `[FINISHED]` per `agent-communication` skill.
Include in the signal:

- The **absolute path** of the report file written to `thinking/`.
- A brief summary (3–5 bullets) of the key findings.

The orchestrator will read the full report from disk and display it to the user.
