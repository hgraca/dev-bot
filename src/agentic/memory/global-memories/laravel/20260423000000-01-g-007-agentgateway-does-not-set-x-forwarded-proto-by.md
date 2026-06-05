---
date: 2026-04-23
keywords: ["laravel"]
---

## G-007: Agentgateway does not set X-Forwarded-Proto by default

- **Problem**: Agentgateway terminates TLS and forwards to backends as plain HTTP, but does NOT set the `X-Forwarded-Proto` header. Backends (Laravel, Core) detect HTTP and redirect to HTTPS → infinite loop (`ERR_TOO_MANY_REDIRECTS`).
  Create an `AgentgatewayPolicy` targeting the Gateway with `traffic.transformation.request.set` to add `X-Forwarded-Proto: request.scheme`. File: `agentgateway-forwarded-headers.yaml` in `default/apps/agentgateway/`.
- **Impact**: Affects ALL services behind TLS termination that enforce HTTPS. Must be included in production migration.
