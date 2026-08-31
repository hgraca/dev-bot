---
date: 2026-05-15
keywords: ["k8s", "cluster"]
---

## k3d multi-cluster on loopback aliases

To run multiple k3d clusters on the same ports (80/443/6443) without conflicts, bind each to a different loopback IP (127.0.0.1, 127.0.0.2, 127.0.0.3, ...). In `k3d/cluster-config.yaml`:

- `ports: [{port: "127.0.0.X:80:80", nodeFilters: [loadbalancer]}, ...]`
- `kubeAPI: {hostIP: "127.0.0.X", hostPort: "6443"}`
- Update `kubeconfig.yaml` server URL and `/etc/hosts` to match.
  This PoC uses `127.0.0.3`. Linux resolves the entire 127.0.0.0/8 block to lo by default — no extra config needed.
