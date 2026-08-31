---
date: 2026-05-01
keywords: ["signoz", "helm", "chart"]
---

## SigNoz Helm service naming: release-name deduplication

When release name matches component name (both "signoz"), the chart doesn't produce "signoz-signoz" — it just creates service `signoz`. Ingress must target service name `signoz` on port 8080, not `signoz-signoz:3301` or `signoz-frontend:3301`.
Fix: Use `name: signoz`, `port.number: 8080` in ingress backend.
