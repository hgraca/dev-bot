---
date: 2026-10-29
keywords: ["k8s", "kubectl", "rbac", "can-i", "subresource"]
trigger-on: ["kubectl-rbac-verification"]
---

## `kubectl auth can-i create pods/exec` measures the wrong permission

`kubectl auth can-i create pods/exec` parses the part after the slash as a resource **name**, not a subresource, so it answers "may I create a pod called `exec`" — which is `yes` for anyone with `create` on `pods`. It never checks the subresource, so an RBAC review that relies on it concludes that exec, attach, portforward and token creation are granted when they are not (or vice versa). Use `kubectl auth can-i create pods --subresource=exec` (kubectl 1.24+), and read `kubectl auth can-i --list` for the subresource rules themselves. Verified on EKS 1.35: `create pods/exec` → yes, `create pods --subresource=exec` → no, with the same credentials.
