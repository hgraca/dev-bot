---
date: 2026-06-18
keywords: ["signoz", "k8s-infra", "otlp", "compression"]
---

## k8s-infra chart OTLP exporter needs gzip compression for SigNoz

The SigNoz k8s-infra chart v0.16.0 OTLP gRPC exporter does not enable compression by default. When exporting directly to a self-hosted SigNoz OTLP gateway (behind Traefik/TLS), the connection fails with `authentication handshake failed: EOF` unless `compression: gzip` is explicitly configured. Fix: add `compression: gzip` under both `otelAgent.config.exporters.otlp` and `otelDeployment.config.exporters.otlp` in the Helm values.
