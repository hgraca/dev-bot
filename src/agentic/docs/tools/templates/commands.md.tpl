---
layout: page
title: "Slash commands"
description: "Slash commands for opencode and claudecode agents — shortcuts for common workflows."
nav_section: docs
---

## Structure

A command is a markdown file — `name`/`description` frontmatter plus an instruction body — living in
a module's `commands/` dir: `src/agentic/<module>/` for agentic modules,
`src/tools/<module>/` for tool modules.

Arguments reach the body two ways. `$ARGUMENTS` is the whole argument tail as one string — use it when
the argument is free-form prose (`devbot:auto-dev` takes the task itself). `$1`, `$2`, … are
positional, one per argument — use them when the argument has a fixed shape (a path, a branch, a PR
URL).

Installation symlinks **each file** into `.agents/commands/`, flat, named after its full frontmatter
`name:`:

```
<devbot-install-path>/src/agentic/<module>/commands/<file>.md   — canonical source
<devbot-install-path>/src/tools/<module>/commands/<file>.md

<project-root>/.agents/commands/devbot:<id>.md   — symlink to the source file
<project-root>/.opencode/commands/               — symlink to .agents/commands/
<project-root>/.claude/commands/                 — symlink to .agents/commands/
```

The link name is what the hosts read, though they join it differently: opencode 2.x turns the path
below `commands/` into the name with `/` separators, claudecode joins the directory with `:`. A flat
`devbot:gh-release.md` is therefore `/devbot:gh-release` on both, and a host that reads the
frontmatter `name:` instead lands on the same id, because the link is named from that frontmatter.
The retired category farm nested the file under `devbot/`, so opencode read `devbot/gh-release`
before the two were aligned.

## Commands

<!-- GENERATED:COMMANDS -->
