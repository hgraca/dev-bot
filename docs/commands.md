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

| Module  | Command                | Description                                                                                                           |
| ------- | ---------------------- | --------------------------------------------------------------------------------------------------------------------- |
| aws     | aws-setup †            | Manual fallback — run these steps by hand when `devbot install` was non-interactive (no TTY)                          |
| dev     | make-tests             | Write tests for the current changeset                                                                                 |
| devteam | code-review            | Review the current changeset against the default branch                                                               |
| devteam | improve-planning       | Iterate on how we plan a story, to improve the process                                                                |
| explore | create-codebase-report | Create a report of the codebase in .agents/memory/active/project.md                                                   |
| explore | gather-context         | Based on a few keywords, gather context from memories, git status, and codebase insights.                             |
| memory  | audit-memory           | Audit the memory vault — check folder placement, latent note quality, thinking/ hygiene, and issue folder consistency |
| memory  | prune-memories         | Prune the memory vault — remove stale entries, merge complementary notes, rewrite incomplete ones                     |
| memory  | remember-session       | Remember any worthwhile learnings from this session                                                                   |
| signoz  | fix-n+1-problems       | Investigate and fix N+1 query problems in the Database Query Performance dashboard                                    |
| signoz  | fix-slow-queries       | Investigate and fix slow database queries in the Database Query Performance dashboard                                 |

† `aws-setup` is a manual fallback runbook, not a registered slash command — it has no `name`/`description` frontmatter.
