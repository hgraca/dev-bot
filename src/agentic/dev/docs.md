---
title: "Dev"
description: "Software-development conventions — craft rules, tests, review resolution, make, and shell strategy."
commands: ["make-tests"]
skills: ["address-review", "make-tests", "makefile", "shell-strategy", "software-development"]
---

The generic craft rules every dev-bot task leans on — independent of language or role.

## What it does

- **`software-development`** — the hub skill: code-quality principles, the tests-first discipline, and the commit protocol. Loaded at session start in every project where code is written.
- **`make-tests`** (skill and command) — test strategy and conventions.
- **`address-review`** — resolving code-review comments.
- **`makefile`** — running project commands through `make`.
- **`shell-strategy`** — choosing between the bash tool and a PTY session.

## Configuration

No project configuration is required.

## See also

- [DevTeam](/modules/agentic/devteam) — the multi-agent workflow built on these conventions
- [Git](/modules/agentic/git) — the commit protocol's home
