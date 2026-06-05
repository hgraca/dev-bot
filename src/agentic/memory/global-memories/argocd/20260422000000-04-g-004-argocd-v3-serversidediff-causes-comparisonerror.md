---
date: 2026-04-22
keywords: ["argocd", "application"]
---

## G-004: ArgoCD v3 ServerSideDiff causes ComparisonError

- **Problem**: Setting `argocd.argoproj.io/compare-options: ServerSideDiff=true` on an Application in ArgoCD v3.0+ can cause `ComparisonError` instead of helping. This happened on the `agentgateway` Application.
- **Root cause**: ArgoCD v3 already ignores `.status` fields by default via annotation-based tracking. Adding `ServerSideDiff` on top introduces server-side diff behavior that can conflict.
  Remove `ServerSideDiff=true`, `ignoreDifferences`, and `RespectIgnoreDifferences=true` annotations. ArgoCD v3 defaults handle status fields correctly.
