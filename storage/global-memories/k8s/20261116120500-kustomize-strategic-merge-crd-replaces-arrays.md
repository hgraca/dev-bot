---
date: 2026-11-16
keywords: ["k8s", "kustomize", "strategic-merge", "crd", "scaledjob"]
aliases: ["patches strategic merge", "unstructured patch", "containers replaced"]
trigger-on: ["kustomize-patch-crd"]
---

## kustomize replaces arrays on a CRD strategic-merge patch

kustomize only performs a real strategic merge for types it knows (built-in `apps`/`batch` kinds). For a CRD — KEDA `ScaledJob`, Argo `Application`, anything from an operator — it treats the object as unstructured and degrades to a JSON merge, where **arrays are replaced wholesale**. A patch carrying `spec.jobTargetRef.template.spec.containers: [{name: runner, env: [...]}]` therefore strips every other container and every other field on that container, and the workload still renders successfully — the damage appears only at deploy time. Patch CRDs with JSON6902 instead (`op: add path: /spec/jobTargetRef/template/spec/containers/0/env/-`), asserting the field exists first; use `op: add` at `.../env` with a full list only when the container has no `env`. A companion hazard on the built-in kinds: a strategic merge on `containers` *adds* a container when the name is absent, so a regex `target.name` can silently create a half-empty container on a workload that never had it — target each workload by exact name and name the container explicitly.
