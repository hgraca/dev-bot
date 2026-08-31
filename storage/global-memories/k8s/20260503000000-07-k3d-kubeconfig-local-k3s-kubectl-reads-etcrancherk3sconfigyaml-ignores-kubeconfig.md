---
date: 2026-05-03
keywords: ["k8s", "kubectl", "cluster"]
---

## k3d kubeconfig: local k3s kubectl reads /etc/rancher/k3s/config.yaml, ignores ~/.kube/config

If you have a local k3s installation, its bundled kubectl (`/usr/local/bin/kubectl` from k3s) reads `/etc/rancher/k3s/config.yaml` instead of `~/.kube/config`. The k3d kubeconfig merge has no effect. After `k3d cluster start`, the API port changes (random mapping) and kubectl can't connect.
Fix: Set `export KUBECONFIG=~/.kube/config` explicitly, or use a non-k3s kubectl binary, or run `k3d kubeconfig merge --kubeconfig-merge-default` and switch context.
