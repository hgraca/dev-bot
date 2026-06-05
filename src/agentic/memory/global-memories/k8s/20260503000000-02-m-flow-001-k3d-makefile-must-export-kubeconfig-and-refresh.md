---
date: 2026-05-03
keywords: ["k8s", "kubectl", "cluster"]
---

## M-FLOW-001: k3d Makefile must export KUBECONFIG and refresh after start/create

`make up` (resume) failed because kubectl targeted wrong port after k3d restart.
Always `export KUBECONFIG := $(HOME)/.kube/config` at Makefile top AND run `k3d kubeconfig merge <cluster> --kubeconfig-merge-default --kubeconfig-switch-context` after both `k3d cluster create` and `k3d cluster start`. The API port is randomized on each start.

## See also

- [[PDRs]]
- [[ADRs]]
- [[patterns]]
- [[gotchas]]
