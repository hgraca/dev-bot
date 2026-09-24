---
title: "DevBot"
description: "The pair-programming agent, with the Expert and Designer subagents it delegates to."
agents: ["designer", "devbot", "expert"]
---

The default way to work with dev-bot: one agent beside you, not over you.

## What it does

- **`devbot`** — the primary pair-programming agent. Works in small increments, suggests before writing, asks before acting, and never runs autonomously.
- **`expert`** — a subagent for deep technical problem analysis on a higher-grade model. It traces root causes and proposes options with trade-offs, and never writes code.
- **`designer`** — a subagent covering UX and UI: interaction specs, screen designs, visual acceptance criteria, and visual validation of implemented UI.

## How it is used

Set `devbot` as the session agent (`default_agent` in `opencode.jsonc`) and it drives one lifecycle stage at a time — DEFINE, PLAN, BUILD, VERIFY, REVIEW, SHIP — delegating only context-gathering, deep analysis, design and review to its subagents.

## Configuration

No project configuration is required — `devbot init` creates the harness config with `devbot` as the default agent.

## See also

- [DevTeam](/modules/agentic/devteam) — the full-delegation alternative
- [Agents](/agents) — the complete roster
