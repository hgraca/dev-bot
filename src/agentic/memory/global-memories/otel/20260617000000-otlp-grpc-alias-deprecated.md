---
date: 2026-06-17
keywords: ["otel", "otlp", "grpc", "exporter"]
---

## OTel v0.154.0 deprecates `otlp` exporter alias — use `otlp_grpc` for gRPC

In OTel Collector v0.154.0, the `otlp` exporter type for gRPC produces a deprecation warning: `"otlp" alias is deprecated; use "otlp_grpc" instead`. The alias may still function but should be renamed to `otlp_grpc` for clean operation. Change exporter names from `otlp/signoz` to `otlp_grpc/signoz` and update all pipeline `exporters:` references accordingly. This applies whether the exporter is named with a slash suffix (e.g., `otlp/signoz` → `otlp_grpc/signoz`) or standalone.
