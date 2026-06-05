---
date: 2026-06-15
keywords: ["otel", "ottl", "transform", "attributes", "resource.attributes"]
---

## OTTL transform syntax changed in OTel Collector 0.120.x

In OTel Collector contrib v0.120.x, OTTL transform statements using `attributes["name"]` without a scope prefix are auto-rewritten to `resource.attributes["name"]` at startup, generating an info-level warning: "one or more statements were modified to include their paths context, please rewrite them accordingly."

Fix: use explicit scope prefix in OTTL statements:

- `attributes["host.name"]` → `resource.attributes["host.name"]`
- `attributes["k8s.node.name"]` → `resource.attributes["k8s.node.name"]`

This applies to `transform` processor `metric_statements`, `log_statements`, and `trace_statements` with `context: resource`. The old syntax still works but the warning clutters logs.
