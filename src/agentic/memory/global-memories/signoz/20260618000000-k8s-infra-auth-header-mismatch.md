---
date: 2026-06-18
keywords: ["signoz", "k8s-infra", "auth"]
---

## k8s-infra chart auth header mismatch with self-hosted SigNoz

The k8s-infra chart's OTLP exporter template hardcodes `signoz-access-token` header (SigNoz Cloud convention). Self-hosted SigNoz with `bearertokenauth` extension expects `Authorization: Bearer <token>`. Fix: override via `otelAgent.config.exporters.otlp.headers.Authorization` and `otelDeployment.config.exporters.otlp.headers.Authorization` with value `"Bearer ${env:SIGNOZ_API_KEY}"`. Helm's `mustMergeOverwrite` deep-merges the maps — both headers will be present, and the SigNoz gateway ignores the unrecognized `signoz-access-token`. Token env var name is `SIGNOZ_API_KEY` (chart convention), not `SIGNOZ_OTLP_TOKEN` (custom convention). Use `apiKeyExistingSecretName` + `apiKeyExistingSecretKey` to reference existing Secret.
