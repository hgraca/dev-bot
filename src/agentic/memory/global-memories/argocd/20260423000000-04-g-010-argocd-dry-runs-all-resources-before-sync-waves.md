---
date: 2026-04-23
keywords: ["argocd", "sync-wave", "sync"]
---

## G-010: ArgoCD dry-runs ALL resources before sync-waves execute

- **Problem**: In an app-of-apps pattern where child apps install CRDs (e.g. `agentgateway-crds` at sync-wave -3) and the parent app also contains resources that use those CRDs (e.g. `Gateway` at sync-wave 0), ArgoCD validates/dry-runs all resources before starting any sync-wave. If the CRD doesn't exist on the cluster, dry-run fails with "The Kubernetes API could not find version X of Y".
  Add `argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true` to EVERY resource that depends on a CRD being installed by an earlier sync-wave. This includes: Gateway, HTTPRoute, GRPCRoute (Gateway API CRDs), and AgentgatewayPolicy (Agentgateway CRDs).
