---
date: 2026-11-20
keywords: ["k8s", "preserve_client_ip", "load-balancer-controller", "nlb", "classic-elb"]
aliases: ["client ip preservation", "source address preservation", "target group attribute"]
trigger-on: ["eks-load-balancer-service", "nlb-client-ip"]
---

## `preserve_client_ip` only applies when the target group is created — and a Classic ELB has no target group at all

Two traps, both hit in one session on the same gateway.

**The attribute is create-only.** `service.beta.kubernetes.io/aws-load-balancer-target-group-attributes: preserve_client_ip.enabled=true` is read once, when the AWS Load Balancer Controller provisions the target group. Adding it to an existing Service changes nothing, and no amount of resync fixes it — the target group must be recreated. Since a target group is only created with its Service, that means recreating the Service (and therefore the load balancer, and therefore the DNS record pointing at it). Plan the change as an LB replacement, not a config edit.

**Check which controller owns the Service before trusting any `aws-load-balancer-*` annotation.** A Service with no `loadBalancerClass` may be served by the legacy in-tree cloud provider, which creates a **Classic** ELB. Classic ELBs have no target group, so every LBC annotation — scheme, target-group-attributes, subnets — is inert, and only `externalTrafficPolicy` has any effect. The tell: Classic ELBs appear only in the classic ELB API (`aws elb describe-load-balancers`), never in `aws elbv2 describe-load-balancers`, and their DNS name is `<32-hex>-<10-digits>.<region>.elb.amazonaws.com` rather than the controller's `k8s-<ns>-<svc>-<hash>`. Create the Service with `loadBalancerClass: service.k8s.aws/nlb` to move it under the LBC — but note the field is immutable, so it also requires recreating the Service.

Related: moving a Gateway or Service between namespaces always produces a new LB, because the LB belongs to a namespaced Service. A zero-downtime cutover therefore means running two LBs and switching DNS, not moving one.
