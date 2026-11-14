---
title: "DevTeam"
description: "The multi-agent team — a TeamLead orchestrator and nine specialists, with planning and implementation workflows."
agents: ["architect", "critic", "developer", "po", "reviewer", "scout", "security", "teamlead", "tester"]
commands: ["code-review", "improve-planning"]
skills: ["implement-plan", "implement-story", "make-plan", "review-implementation", "review-plan", "summarize-plan"]
---

A full engineering team in one session: a teamlead that classifies work and routes it to specialists, and the workflows that keep planning and implementation honest.

## What it does

- **Orchestration** — `teamlead` classifies a request and delegates; it never writes code or tests itself.
- **Planning** — `make-plan` drives po → architect → critic until the plan is approved; `review-plan` stress-tests a draft before code exists; `summarize-plan` writes the planning summary.
- **Implementation** — `implement-story` runs the tester → developer → reviewer cycle per task; `implement-plan` executes an approved plan step by step.
- **Review** — `review-implementation` reviews a changeset against the plan; the `code-review` command reviews the current changeset against the default branch.
- **Specialists** — po, architect, critic, developer, tester, reviewer, scout and security subagents, each with a strictly scoped job (auditors cannot edit).

## Configuration

No project configuration is required.

## See also

- [Polyrepo sessions](/polyrepo-sessions) — how this module scopes itself to the owning project
- [DevBot](/modules/agentic/devbot) — the pair-programming alternative
- [Agents](/agents) — the complete roster
