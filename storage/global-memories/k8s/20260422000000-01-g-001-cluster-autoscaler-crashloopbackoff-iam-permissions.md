---
date: 2026-04-22
keywords: ["k8s", "cluster"]
---

## G-001: cluster-autoscaler CrashLoopBackOff — IAM permissions

- **Problem**: `cluster-autoscaler` in `kube-system` has been in CrashLoopBackOff for 40+ days (11,025+ restarts). The pod crashes immediately on startup.
- **Root cause**: The `NodeInstanceRole` IAM role lacks `autoscaling:DescribeAutoScalingGroups` (and likely other autoscaling permissions). Error: `AccessDenied: User: arn:aws:sts::599001845632:assumed-role/NodeInstanceRole/i-05e3e2178f9389c5f is not authorized to perform: autoscaling:DescribeAutoScalingGroups`.
- **Impact**: Cluster cannot scale up, causing 80+ pending pods across all namespaces. All nodes are at max pod capacity (t3.medium-class, ~17 pods per node).
  Attach an IAM policy with `autoscaling:Describe*`, `autoscaling:SetDesiredCapacity`, `autoscaling:TerminateInstanceInAutoScalingGroup`, `ec2:DescribeLaunchTemplateVersions`, `ec2:DescribeInstanceTypes`, `eks:DescribeNodegroup` to the `NodeInstanceRole`.
