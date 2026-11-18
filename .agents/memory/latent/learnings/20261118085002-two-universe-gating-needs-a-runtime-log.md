---
date: 2026-11-18
keywords: ["devbot", "datasources", "sidecar", "observability", "docker-compose"]
see: ["ADRs/20260930122947-datasources-consumer-gated-sidecars.md"]
---

# A design that spans two universes needs a runtime line, not just an ADR

## Symptom

`storage/datasources/docker-compose.yml` listed `opensearch-prod` and `s3-prod`, `docker ps` showed neither, and `devbot up` had exited 0. No log said why, so a correct state looked like a failed start.

## Cause

Two deliberate universes: the **render** gate reads the machine's configured `projects` (session-independent, so `init.sh`'s port allocation and the manifests cannot drift), the **run** gate reads live sessions. A sidecar only a configured project opts into is therefore rendered and correctly not started — but `up.sh` skipped it with a bare `continue`.

## Rule

When a capability is gated on two different sets (configured vs live, render-time vs run-time), log the **skip** with its reason at the point of divergence. The ADR explains the design to whoever reads the ADR; an operator reading `docker ps` needs the same sentence in the boot log. And verify the composed plan, not only the containers: `docker compose -f <rendered> config --services` over-reports what will actually run.
