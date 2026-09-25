---
date: 2026-09-25
keywords: ["k8s", "eks", "vpc-cni", "addon", "helm"]
trigger-on: ["eks-addon-ownership", "vpc-cni-configuration", "aws-node-daemonset"]
---

## Helm labels on an EKS-managed DaemonSet do not mean a Helm release exists — and add-on config is the durable surface

An `aws-node` (VPC CNI) DaemonSet carrying `app.kubernetes.io/managed-by: Helm` and `helm.sh/chart: aws-vpc-cni-1.21.1` reads as a chart hand-applied by someone, but EKS delivers managed add-ons **through the Helm chart internally**, so those labels are the add-on's own fingerprints; a `kubectl.kubernetes.io/last-applied-configuration` from years earlier is only a pre-add-on remnant, and no `sh.helm.release.v1.*` secret exists either. Establish ownership positively with `aws eks describe-addon --addon-name vpc-cni`, which returns the add-on's version, status and health. Ownership then dictates the supported configuration surface: for an add-on, settings belong in its own schema (`aws eks describe-addon-configuration` lists the permitted keys, and the add-on's `configurationValues` accepts them) or in the `amazon-vpc-cni` ConfigMap — whereas env vars patched directly onto the DaemonSet are **not durable**, because with `resolveConflicts` unset (the default is `OVERWRITE`) EKS owns those fields and reverts customer edits on the next add-on update. Reading the chart's defaults also explains surprising values without blaming an operator: the CNI chart ships `AWS_VPC_K8S_CNI_LOGLEVEL: DEBUG` and `AWS_VPC_K8S_PLUGIN_LOG_LEVEL: DEBUG`, so a cluster matching them exactly has never been tuned at all.
