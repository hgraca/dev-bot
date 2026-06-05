---
date: 2026-05-01
keywords: ["signoz", "helm", "chart"]
---

## SigNoz chart 0.55.1 is broken (stale Docker images)

Chart version 0.55.1 references `bitnami/zookeeper:3.7.1` which no longer exists on Docker Hub. The chart structure also completely differs from 0.121.0 (separate frontend/queryService vs unified signoz binary). Always use chart ≥0.121.0.
Fix: Pin to chart version 0.121.0 in Makefile and values file.
