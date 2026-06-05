---
date: 2026-05-02
keywords: ["signoz", "helm", "chart"]
---

## M-ARCH-001: OTel Demo Helm chart — disable bundled backends via env override

Integrating opentelemetry-demo chart with existing SigNoz stack.
Set `OTEL_COLLECTOR_NAME` env to cross-namespace DNS (`otel-collector.observability.svc.cluster.local`) and disable all `components.{jaeger,prometheus,grafana,opensearch,opentelemetry-collector}.enabled: false`. The chart's services use `$(OTEL_COLLECTOR_NAME):4317` by default. Also disable `frontendProxy.env.GRAFANA_SERVICE_*` and `JAEGER_SERVICE_*` to avoid 502s.
