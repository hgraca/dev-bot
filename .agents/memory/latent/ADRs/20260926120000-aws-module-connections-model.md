---
date: 2026-09-26
keywords: ["aws", "mcp", "connections", "credentials", "iam"]
see: ["ADRs/20260926120100-datasources-sidecar-source-class.md"]
---

## The `aws` module pins one MCP server per named connection

The `aws` module no longer resolves a single global `aws_profile`/`aws_region` or runs the browser `aws login`. Connections are declared once in `.devbot.global.jsonc` under `aws_connections` — a name mapped to `region`, plus `env` (values or `${VAR}` references) **or** `profile`, and an optional `account_id` — and each project opts in by name in `.devbot.project.jsonc`, exactly the `datasources` shape. `init.sh` emits one secret-free dynamic manifest per selected connection (`aws-<connection>`), prunes deselected ones and reconciles `opencode.jsonc`; the module keeps no canonical `mcp.json` (the servers are per-connection and known only at init, so it also leaves the generated mcps aggregate). The launcher takes the connection name, resolves credentials into the process **environment** (never argv — `ps` is world-readable), sources the repo `.env` for `${VAR}`, unsets `AWS_PROFILE` in the env form so the explicit keys win, rejects a connection declaring both forms, and asserts `account_id` via `sts get-caller-identity`. Nothing prompts: `install.sh` installs dependencies and fetches the agent rules, `up.sh` only verifies each declared connection. The caveat that must not be lost: this pin scopes the **MCP path only** — an agent with bash can use any credential the machine holds, so IAM on the identity plus a permission boundary is the actual control.
