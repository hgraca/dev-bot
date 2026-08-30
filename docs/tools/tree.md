---
layout: page
title: Tree
description: Directory tree inspection tool.
nav_section: docs
---

Displays directory structure as a tree — shows all subfolders and files in one or more paths.

## Output formats

- **Markdown** (default): `tree --markdown src/`
- **Plain text**: `tree src/`
- **JSON**: `tree --json src/`

## How agents use it

Used by the `explore` module's `gather-context` skill to understand project structure at session start. Also available as a standalone tool for agents to navigate the codebase.

## See also

- [Git Report](/tools/git-report) — git state snapshot
- [Explore](/module-reference) — gather-context skill
