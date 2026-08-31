---
date: 2026-05-11
keywords: ["otel", "opentelemetry", "collector"]
---

## OpenTelemetry collector-contrib `0.115.0` does not exist on Docker Hub — use `0.115.1`

The `otel/opentelemetry-collector-contrib:0.115.0` tag was never published (or was yanked); pulls fail with `failed to resolve reference … not found`. The supersede patch `0.115.1` is the canonical 0.115 release. Other adjacent minors are unaffected (`0.116.0/.1`, `0.117.0`, `0.118.0`, `0.119.0`, `0.120.0` all exist). Symptom: `ImagePullBackOff` on the producer/gateway Deployment, `kubectl rollout status deployment/<name> --timeout=120s` errors.
Fix: Pin to `0.115.1` (or move to `0.120.0+`). Always verify a tag exists before pinning: `docker manifest inspect otel/opentelemetry-collector-contrib:<tag>` or `curl https://hub.docker.com/v2/repositories/otel/opentelemetry-collector-contrib/tags?name=<minor>`.
