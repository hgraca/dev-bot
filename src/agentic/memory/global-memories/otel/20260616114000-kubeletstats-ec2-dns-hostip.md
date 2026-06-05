---
date: 2026-06-16
keywords: ["otel", "kubeletstats", "eks", "dns", "hostIP"]
---

## Kubelet stats receiver on EKS: use status.hostIP not spec.nodeName for endpoint

On EKS/EC2, `spec.nodeName` returns the EC2 internal DNS name (e.g. `ip-172-30-101-34.eu-central-1.compute.internal`). CoreDNS in Kubernetes cannot resolve `.internal` hostnames — they are AWS-private. When the OTel collector's `kubelet_stats` receiver uses `${env:K8S_NODE_NAME}:10250` as its endpoint, DNS resolution fails and kubelet metrics stop flowing. Fix: add an env var from `fieldRef: status.hostIP` (the node's IP) and use `${env:K8S_NODE_IP}:10250` instead. Keep `K8S_NODE_NAME` if it's still used elsewhere (e.g. `host.name` tagging).
