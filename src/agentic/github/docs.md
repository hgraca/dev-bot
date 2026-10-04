---
title: "GitHub"
description: "Open a pull request from a branch, or work one locally — check out its changeset, or address its review comments."
commands: ["gh-address-review", "gh-make-review", "gh-create-pr"]
skills: ["gh-create-pr"]
---

Open a pull request from a branch, or pull one down and work on it locally — review its changeset, or
address the comments it already has.

## What it does

- **`gh-create-pr`** — opens a pull request from a branch onto the default branch. The module's only write
  back to GitHub.
- **`gh-make-review`** — checks out a PR and code-reviews its changeset locally.
- **`gh-address-review`** — reads a PR's review comments and addresses them locally.

`gh-create-pr` is the one write the module makes to GitHub: creating the pull request, plus the
`git push -u origin <branch>` a never-pushed branch needs. The review commands keep their output
local — no replies, comments or resolutions are ever posted back.

## Configuration

Needs the `gh` CLI, authenticated on the machine; the module's lifecycle scripts install and update it.
No project configuration is required.

## See also

- [Git](/modules/agentic/git) — the commit and history skills these commands lean on
- [Self-improvement](/modules/agentic/self-improvement) — improving what the reviewer catches
