---
layout: page
title: Slash commands
description: Slash commands for opencode and claudecode agents — shortcuts for common workflows.
nav_section: docs
---

## Structure

A command is a markdown file — `name`/`description` frontmatter plus an instruction body (`$1`, `$2`,
… for arguments) — living in a module's `commands/` dir: `src/agentic/<module>/` for agentic modules,
`src/tools/<module>/` for tool modules.

Installation symlinks **each file** into a single `devbot/` category, named after the frontmatter
`name:` with the `devbot:` prefix stripped:

```
<devbot-install-path>/src/agentic/<module>/commands/<file>.md   — canonical source
<devbot-install-path>/src/tools/<module>/commands/<file>.md

<project-root>/.agents/commands/devbot/<bare-name>.md   — symlink to the source file
<project-root>/.opencode/commands/                      — symlink to .agents/commands/
<project-root>/.claude/commands/                        — symlink to .agents/commands/
```

The per-file layout (rather than one symlink per module) is what makes both harnesses expose the same
name: opencode reads the frontmatter `name:` (`devbot:release`), while claudecode derives `<dir>:<file>`
from the path — a module-level symlink would render `devbot:devbot-release`.

## Commands

| Module           | Command                    | Description                                                                                                                                                                                                            |
| ---------------- | -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| dev              | make-tests                 | Write tests for the current changeset                                                                                                                                                                                  |
| devbot-cli       | audit                      | Audit the dev-bot setup in the current project and report what did not work                                                                                                                                            |
| devbot-cli       | audit-fix                  | Address the issues flagged by a `devbot:audit` report                                                                                                                                                                  |
| devteam          | code-review                | Review the current changeset against the default branch                                                                                                                                                                |
| devteam          | improve-planning           | Iterate on how we plan a story, to improve the process                                                                                                                                                                 |
| explore          | create-project-report      | Create a report of the codebase in .agents/memory/active/project.md                                                                                                                                                    |
| explore          | gather-context             | Based on a few keywords, gather context from memories, git status, and codebase insights.                                                                                                                              |
| git              | commit                     | Commit the current changeset                                                                                                                                                                                           |
| git              | release                    | Cut a release — merge to the default branch, tag it, push to the chosen remotes, and publish the GitHub releases                                                                                                       |
| github           | gh-address-review          | Review a GitHub PR and address its review comments locally                                                                                                                                                             |
| github           | gh-make-review             | Check out a GitHub PR and code-review its changeset locally                                                                                                                                                            |
| memory           | audit-memory               | Audit the memory vault — check folder placement, latent note quality, thinking/ hygiene, and issue folder consistency                                                                                                  |
| memory           | prune-memories             | Prune the memory vault — remove stale entries, merge complementary notes, rewrite incomplete ones                                                                                                                      |
| memory           | remember-session           | Remember any worthwhile learnings from this session                                                                                                                                                                    |
| self-improvement | improve-reviewing          | Iterate on how the @reviewer reviews change sets, to improve the process                                                                                                                                               |
| signoz           | find-db-performance-issues | Find database issues (full table scans, slow queries, N+1, app anti-patterns, lock contention, hardware limitations) driving DB load, using SigNoz; each query finding reports executions/day, median and p95 duration |
