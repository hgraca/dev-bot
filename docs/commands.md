---
layout: page
title: Slash commands
description: Slash commands for opencode and claudecode agents — shortcuts for common workflows.
nav_section: docs
---

## Structure

All command files live in their module's `commands/` dir under `src/agentic/`.
Both opencode and claudecode harnesses use relative symlinks to reach them:

```
<devbot-install-path>/src/agentic/<module>/commands/    — canonical source

<project-root>/.agents/commands/<module>   — symlink to source (one per module)
<project-root>/.opencode/commands/         — symlink to .agents/commands/
<project-root>/.claude/commands/           — symlink to .agents/commands/
```

## Commands

| Module  | Command                    | Description                                                                                                                                                                                                            |
| ------- | -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| dev     | make-tests                 | Write tests for the current changeset                                                                                                                                                                                  |
| devteam | code-review                | Review the current changeset against the default branch                                                                                                                                                                |
| devteam | improve-planning           | Iterate on how we plan a story, to improve the process                                                                                                                                                                 |
| explore | create-project-report      | Create a report of the codebase in .agents/memory/active/project.md                                                                                                                                                    |
| explore | gather-context             | Based on a few keywords, gather context from memories, git status, and codebase insights.                                                                                                                              |
| github  | gh-review                  | Review a GitHub PR and address its review comments locally                                                                                                                                                             |
| memory  | audit-memory               | Audit the memory vault — check folder placement, latent note quality, thinking/ hygiene, and issue folder consistency                                                                                                  |
| memory  | prune-memories             | Prune the memory vault — remove stale entries, merge complementary notes, rewrite incomplete ones                                                                                                                      |
| memory  | remember-session           | Remember any worthwhile learnings from this session                                                                                                                                                                    |
| signoz  | find-db-performance-issues | Find database issues (full table scans, slow queries, N+1, app anti-patterns, lock contention, hardware limitations) driving DB load, using SigNoz; each query finding reports executions/day, median and p95 duration |
