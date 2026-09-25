---
date: 2026-09-25
keywords: ["devbot", "datasources", "gateway", "unreachable", "mcp"]
trigger-on: ["devbot-datasources-gateway", "mcp-sse-unable-to-connect"]
---

## Every datasource unreachable means the gateway is not started at all, by design

When all declared datasources are unreachable, MCP clients fail with `SSE error: Unable to connect. Is the computer able to access the url?` and nothing listens on 18510 — this is deliberate, not a broken client. `src/agentic/datasources/render.sh` asks the real toolbox which sources it can initialize and drops the rest (toolbox treats an unreachable source as a fatal startup error), so with all sources down `storage/datasources/conf/tools.yaml` publishes empty. `up.sh` then finds no `kind: source` via `_catalogue_has_sources` and skips the gateway on purpose, logging `datasources — no usable datasources; gateway not started`: a zero-tool gateway is pure cost. Diagnose with `ss -ltnp` (18510 absent) plus the contents of `conf/tools.yaml` — if it is only the `# No datasources configured…` comment, suspect connectivity rather than the harness: a VPN outage makes RDS resolve to a private IP and `dial i/o timeout`, and a stopped local stack closes 127.0.0.1:3306/6379/27017. Any non-empty reachable subset DOES start the gateway with only those toolsets, so a partial outage surfaces as a connect error on the missing toolsets alone. Restore connectivity and the local containers, then `devbot up` re-renders and starts it.
