---
date: 2026-05-03
keywords: ["k8s", "kubectl", "cluster"]
---

## k3d cluster resume: kubectl may use wrong kubeconfig (local k3s override)

If k3s is installed locally, its bundled kubectl reads `/etc/rancher/k3s/config.yaml` instead of `~/.kube/config`. After `k3d cluster start`, the API port changes but kubectl still targets the old/wrong port. Symptoms: "connection refused" on port 6443 even though Docker containers are up.
Fix: Set `KUBECONFIG=/home/herberto/.kube/config` explicitly, or use `k3d kubeconfig merge --kubeconfig-merge-default` and switch context.
