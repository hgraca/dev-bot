---
date: 2026-04-23
keywords: ["istio"]
---

## M-FLOW-002: Always verify route existence before testing

Hotels-api returned 404 via Agentgateway but 200 via Istio. Root cause was the HTTPRoute never synced because `kustomization.yaml` didn't include it.
Before testing routes, verify they exist: `kubectl get httproutes -A`. A 404 from the gateway can mean either "backend has no handler" or "route doesn't exist" — only `kubectl get` distinguishes them. Compare both gateways to catch discrepancies early.
