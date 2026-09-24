---
title: "GitHub"
description: "Work a pull request locally — check out its changeset, or address its review comments."
commands: ["gh-address-review", "gh-make-review"]
---

Pull a pull request down and work on it locally — review its changeset, or address the comments it already has — with nothing written back to GitHub.

## What it does

- **`gh-make-review`** — checks out a PR and code-reviews its changeset locally.
- **`gh-address-review`** — reads a PR's review comments and addresses them locally.

Both deliberately keep their output local: no replies, comments or resolutions are ever posted back to GitHub.

## Configuration

Needs the `gh` CLI, authenticated on the machine; the module's lifecycle scripts install and update it. No project configuration is required.

## See also

- [Git](/modules/agentic/git) — the commit and history skills these commands lean on
- [Self-improvement](/modules/agentic/self-improvement) — improving what the reviewer catches
