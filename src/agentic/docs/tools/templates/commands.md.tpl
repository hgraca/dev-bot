---
layout: page
title: "Slash commands"
description: "Slash commands for opencode and claudecode agents — shortcuts for common workflows."
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

<!-- GENERATED:COMMANDS -->
