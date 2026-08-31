---
date: 2026-05-04
keywords: ["k8s", "cluster"]
---

## k3d pod DNS: CoreDNS can't reach Docker bridge DNS (172.18.0.1) from pod network

CoreDNS forwards to `/etc/resolv.conf` which points to `172.18.0.1` (Docker embedded DNS). UDP from pod network (10.42.x.x) to Docker bridge times out — works from node namespace but not pod namespace. Root cause unclear (possibly conntrack/NAT interaction). Disabling network-policy and adding iptables DOCKER-USER ACCEPT did NOT fix it.
Fix: Patch CoreDNS configmap to `forward . 8.8.8.8 8.8.4.4` after cluster creation. Also pin `kubeAPI.hostPort: "6443"` in cluster-config.yaml to prevent random API port on restart.
