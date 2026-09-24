---
title: "Datasources"
description: "One shared gateway for a project's databases, with a free-form query tool per source."
skills: ["datasources"]
---

Agents query a project's databases through a single gateway, with one tool per declared datasource — no per-engine wiring.

## What it does

Runs the **MCP Toolbox** gateway as a shared service (port range 18500–18599) and registers the databases a project declares once in the global config and opts into per project. Supported engines: MySQL/MariaDB, Postgres, SQLite, MongoDB and Redis. The `devbot:datasources` skill documents how to query them.

The module renders both the gateway's compose file and its tool definition from the declared sources, so adding a database is a config change, not a code change.

Only databases the gateway can actually initialize are registered. Toolbox treats an unreachable source as fatal at startup **and** on reload, so one down database would otherwise take the whole shared gateway down with it.

## Configuration

Each database is declared once in `.devbot.global.jsonc` under `datasources`, with its engine `type` and `url`:

```jsonc
"datasources": {
  "my-db": { "enabled": true, "type": "postgres", "url": "postgres://user:pass@host:5432/db" }
}
```

A project then selects which declared sources it wants in `.devbot.project.jsonc`; a source that is selected but not declared warns, and one no longer selected is unregistered from the gateway.

## See also

- [MCP configuration](/mcp-config) — the manifest schema and the shared gateways
- [Configuration](/configuration) — the global config keys
