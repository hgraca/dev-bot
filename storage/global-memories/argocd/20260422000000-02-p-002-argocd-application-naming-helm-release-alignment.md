---
date: 2026-04-22
keywords: ["argocd", "application"]
---

## P-002: ArgoCD Application naming — Helm release alignment

- **Pattern**: ArgoCD Application `metadata.name` must match the Helm release name when `spec.source.helm` is used. Mismatch causes Helm to create a new release instead of managing the existing one.
- **When**: Creating or renaming ArgoCD Application resources that use Helm charts.
