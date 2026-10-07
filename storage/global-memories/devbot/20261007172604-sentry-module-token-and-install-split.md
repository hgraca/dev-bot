---
date: 2026-10-07
keywords: ["devbot", "sentry", "mcp", "skills"]
aliases: ["SENTRY_ACCESS_TOKEN", "sentry devbot module config", "SENTRY_TOKEN"]
trigger-on: ["devbot-sentry-module"]
---

## The dev-bot sentry module: token name, install/register split, and `enabled: false` reality

The dev-bot `sentry` module (`src/agentic/sentry/`) wires Sentry's hosted MCP (`https://mcp.sentry.dev/mcp`) with the header `Sentry-Bearer {env:SENTRY_ACCESS_TOKEN}` — the env var is **`SENTRY_ACCESS_TOKEN`**, not `SENTRY_TOKEN`, and it is resolved by the client at launch, never written to a config. MCP registration and skill installation are separate concerns: the MCP is auto-registered per-project from `mcp.json` on reinit, but the 8 agent skills are fetched by a **machine-level** `install.sh` (`npx skills add getsentry/agent-plugin`) and only symlinked into the project's `.opencode/skills/sentry` by a per-project `init.sh` — so a module enabled only per-project yields a working MCP with no skills. The manifest ships `enabled: false` ("registered but not started"), yet the MCP tools remain reachable in practice despite it (a known, audited dev-bot contradiction). `oauth: false` is deliberate, so opencode does not race token auth with OAuth discovery.
