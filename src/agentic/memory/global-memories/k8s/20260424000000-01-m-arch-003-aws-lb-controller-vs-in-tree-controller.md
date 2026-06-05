---
date: 2026-04-24
keywords: ["k8s"]
---

## M-ARCH-003: AWS LB Controller vs in-tree controller — different defaults

Production agentgateway NLB was unreachable. curl hung on TCP connect. NLB resolved to private IPs (172.29.x.x).
AWS Load Balancer Controller and in-tree cloud controller have different default schemes. AWS LBC → internal (private). In-tree → internet-facing (public). NLB naming reveals which controller manages it: `k8s-<ns>-<name>-*` = AWS LBC, UUID-style = in-tree. Always check `nslookup` for public vs private IPs when debugging NLB connectivity.
