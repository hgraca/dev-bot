---
title: "DevBot"
description: "The pair-programming agent, with the Expert and Designer subagents it delegates to."
agents: ["designer", "devbot", "expert"]
commands: ["reload-datasources", "auto-dev", "stats"]
---

The default way to work with dev-bot: one agent beside you, not over you.

## What it does

- **`devbot`** — the primary pair-programming agent. Works in small increments, suggests before writing, and asks before acting; it runs autonomously only when you invoke `auto-dev`.
- **`expert`** — a subagent for deep technical problem analysis on a higher-grade model. It traces root causes and proposes options with trade-offs, and never writes code.
- **`designer`** — a subagent covering UX and UI: interaction specs, screen designs, visual acceptance criteria, and visual validation of implemented UI.
- **`reload-datasources`** — re-evaluates the datasource catalogue and verifies the shared gateway serves it: the recovery path for a database behind a VPN that was down when `devbot` started, instead of restarting the session.
- **`auto-dev`** — the opt-in autonomous mode: take a task given inline, as a file path or as a URL, or continue the assignment already in progress; refine it once when its outcome is open, then follow the workflow in use without its check-ins, self-review, then iterate on the pull-request review until it is clean — stopping one step before the merge.
- **`stats`** — run the tool and MCP usage report for the harness actually in use, then read it back as working well / can be improved / not working at all, one line per item.

## How it is used

Set `devbot` as the session agent (`default_agent` in `opencode.jsonc`) and it drives one lifecycle stage at a time — DEFINE, PLAN, BUILD, VERIFY, REVIEW, SHIP — delegating only context-gathering, deep analysis, design and review to its subagents.

## Configuration

No project configuration is required — `devbot init` creates the harness config with `devbot` as the default agent.

## See also

- [DevTeam](/modules/agentic/devteam) — the full-delegation alternative
- [Agents](/agents) — the complete roster
