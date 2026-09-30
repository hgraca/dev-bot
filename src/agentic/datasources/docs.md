---
title: "Datasources"
description: "One shared gateway for a project's databases and data stores — a free-form query tool per source, or a sidecar server where toolbox has none."
skills: ["datasources"]
---

Agents reach a project's data sources through one declared catalogue: a database becomes a free-form query tool on a shared gateway, and a source toolbox cannot host (OpenSearch, S3) becomes its own small MCP server.

## What it does

Runs the **MCP Toolbox** gateway as a shared service (port range 18500–18599) and registers the sources a project declares once in the config and opts into per project. Engines: MySQL/MariaDB, Postgres, SQLite, MongoDB and Redis. The `devbot:datasources` skill documents how to query them.

Sources with no toolbox engine are **sidecars**: a small MCP server in its own container, on its own port, declared with the same `type` + `env` shape — `opensearch` (the OpenSearch project's server) and `s3` (dev-bot's own read-only server). See [Configuration](#configuration).

The module renders the gateway's compose file, its tool definition, and every sidecar service from the declared sources, so adding a source is a config change, not a code change.

Only databases the gateway can actually initialize are registered. Toolbox treats an unreachable source as fatal at startup **and** on reload, so one down database would otherwise take the whole shared gateway down with it. Sidecars are **not** probed: each is its own container, so it cannot take anything else down with it — one that fails to start fails only its own manifest.

## Configuration

Each source is declared once in `.devbot.global.jsonc` under `datasources`, with its engine `type` and an `env` map of literals or `${VAR}` references:

```jsonc
"datasources": {
  "hotels-dev": {
    "type": "mysql",
    "env": { "MYSQL_HOST": "localhost", "MYSQL_USER": "root", "MYSQL_PASSWORD": "${HOTELS_DEV_DB_PASSWORD}" }
  },
  "prod-search": {
    "type": "opensearch",
    "env": {
      "OPENSEARCH_URL": "https://search.example.com",
      "AWS_REGION": "eu-central-1",
      "AWS_ACCESS_KEY_ID": "${OS_KEY_ID}",
      "AWS_SECRET_ACCESS_KEY": "${OS_SECRET}"
    }
  }
}
```

A project then selects which declared sources it wants in `.devbot.project.jsonc`; a source that is selected but not declared warns, and one no longer selected is unregistered from the harness.

Sidecar credentials are environment variables too — nothing mounts `~/.aws` into a sidecar, so an AWS-facing one takes the standard credential variables rather than a profile. The [AWS module](/modules/agentic/aws#setting-up-the-identity) documents the read-only IAM policy and the steps that produce the key pair.

## Lifecycle

A sidecar is **demand-gated**, not merely module-gated. It is rendered into the gateway's compose file only when a project listed in `.devbot.global.jsonc::projects` — or the project being wired — opts into it, and it **runs** only while a live `devbot` session serves such a project. The toolbox gateway is unaffected: it keeps its own availability filter, because one unreachable database would otherwise take it down (see [What it does](#what-it-does)).

Two things follow. A sidecar whose last consumer's session exits is stopped — by `reconcile.sh`, which the session registry runs on every non-final session exit (the last exit tears the whole gateway down) — so a project that wants nothing does not pay for another project's sidecar. And a sidecar's port is allocated from the same demand-filtered catalogue the compose is rendered from, so a manifest URL and its service listener cannot drift. The render side is deliberately session-independent (`.devbot.global.jsonc::projects` plus the project being wired), because ports are allocated at reinit, before a session exists.

Sidecars run on the `uv` image and resolve their server's dependencies at container start, so a shared cache under `storage/datasources/uv-cache` (mounted at `/var/cache/uv`) keeps a restart warm.

## See also

- [MCP configuration](/mcp-config) — the manifest schema and the shared gateways
- [Configuration](/configuration) — the global config keys
