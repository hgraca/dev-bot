---
date: 2026-04-24
keywords: ["istio"]
---

## G-011: AWS Load Balancer Controller defaults NLB to internal scheme

- **Problem**: When agentgateway creates a LoadBalancer Service for the Gateway, the AWS Load Balancer Controller creates an NLB with `internal` scheme (private IPs only). The in-tree cloud controller (used by Istio) defaults to `internet-facing` (public IPs). This is a silent regression — the NLB gets created, DNS resolves, but connections hang from outside the VPC.
  Add `spec.infrastructure.annotations` to the Gateway resource with `service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing`. This passes the annotation to the auto-generated Service.
- **Detection**: `nslookup <nlb-hostname>` — private IPs (172.x.x.x) = internal, public IPs = internet-facing.
