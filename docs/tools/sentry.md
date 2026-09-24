---
layout: page
title: Sentry
description: Error monitoring and production issue triage.
nav_section: docs
---

Sentry error-monitoring integration. The module wires Sentry's hosted MCP server (`https://mcp.sentry.dev/mcp`) with a token header, and installs the official Sentry agent skills for setup, instrumentation and issue debugging.

The server needs `SENTRY_ACCESS_TOKEN` in the environment — the header is `Sentry-Bearer {env:SENTRY_ACCESS_TOKEN}`, so the token is expanded by the client at launch and never written to a config file. Because a token is the auth path, `oauth` is explicitly `false`: opencode must not race it with OAuth discovery.

The module ships one command, `devbot:find-sentry-issues`, which ranks open issues by user impact, pulls full context and maps each finding to the offending code.

## See also

- [Module Reference](/module-reference) — full module directory
- [MCP configuration](/mcp-config) — the canonical manifest schema, including header auth
