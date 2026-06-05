---
date: 2026-04-24
keywords: ["k8s", "kubectl"]
---

## G-015: "Too many pods" vs resource exhaustion — different root cause

- **Problem**: `0/7 nodes are available: 7 Too many pods` is NOT the same as CPU/memory exhaustion. This means every node has hit its ENI-based pod count limit (t3.medium ≈ 17 pods). The node may have plenty of CPU/memory but still can't accept pods.
- **Detection**: `kubectl describe node | grep -A5 "Allocatable" | grep pods` to see per-node pod limits. Compare against `kubectl get pods --all-namespaces --field-selector spec.nodeName=<node> | wc -l`.
