---
date: 2026-09-21
keywords: ["k8s", "eks", "aws-cni", "daemonset", "rollout"]
trigger-on: ["eks-daemonset-rollout", "aws-cni-ip-assignment"]
---

## EKS DaemonSet rollouts stall with `aws-cni failed to assign an IP address`

On EKS, rolling a DaemonSet can leave pods stuck `0/1 Running` behind repeated `FailedCreatePodSandBox` events reading `plugin type="aws-cni" name="aws-cni" failed (add): add cmd: failed to assign an IP address to container`. This is node-level IP capacity rather than a scheduling or manifest problem: small instance types have low ENI/IP ceilings (t3.medium supports 17 pods), and a rolling update cycling one pod per node while applications are also churning can transiently exhaust the free addresses. Diagnose with `kubectl get events --field-selector reason=FailedCreatePodSandBox` plus per-node pod density from `kubectl get pods -A -o wide`. Watch the DaemonSet's status numbers rather than its single `upToDate` field — `desired=N ready<M upToDate=N unavailable>0` reads as "rolled out" if you only look at `upToDate`, when M agents are actually serving. It generally self-resolves as terminating pods release addresses, so observe before intervening, but while it lasts the affected nodes have **no** collector/agent running and their telemetry is silently missing — a gap that only shows up as absent data, never as an error.
