---
title: "Dev"
description: "Software-development conventions — craft rules, tests, review loops and resolution, make, and shell strategy."
commands: ["make-tests"]
skills: ["address-review", "make-tests", "makefile", "review-loop", "shell-strategy", "software-development"]
tools: ["bats-run"]
---

The generic craft rules every dev-bot task leans on — independent of language or role.

## What it does

- **`software-development`** — the hub skill: the workflows a task follows, code-quality principles, the tests-first discipline, and the commit protocol. Loaded at session start in every project where code is written.
- **`make-tests`** (skill and command) — test strategy and conventions.
- **`address-review`** — resolving code-review comments.
- **`review-loop`** — the reviewer-agnostic review→fix cycle: convergence, one fixup per finding, the
  answer rule and the finish. Driven by `@reviewer` locally, or by a pull-request reviewer through
  its adapter.
- **`makefile`** — running project commands through `make`.
- **`shell-strategy`** — choosing between a quick shell call and a long-running channel.

## Configuration

No project configuration is required.

## See also

- [Polyrepo sessions](/polyrepo-sessions) — how this module scopes itself to the owning project
- [DevTeam](/modules/agentic/devteam) — the multi-agent workflow built on these conventions
- [Git](/modules/agentic/git) — the commit protocol's home
