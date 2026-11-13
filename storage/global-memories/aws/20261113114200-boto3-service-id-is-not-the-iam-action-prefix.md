---
date: 2026-11-13
keywords: ["aws", "iam", "elasticloadbalancing", "policy", "elbv2"]
aliases: ["specified in the action does not exist", "elbv2 policy rejected", "service prefix mismatch"]
trigger-on: ["iam-policy-authoring", "elb-permissions"]
---

## The boto3 service id is not the IAM action prefix

A policy statement written as `elasticloadbalancingv2:Describe*` is rejected at save time in the console with **"The service elasticloadbalancingv2:Describe* specified in the action does not exist."** There is no `elasticloadbalancingv2` action namespace. AWS Elastic Load Balancing declares **one** service prefix, `elasticloadbalancing`, covering both classic ELB and ALB/NLB — `elbv2` exists only as the boto3/SDK client id (`boto3.client("elbv2")`).

The same mismatch bites in other services where the SDK splits a product: the IAM prefix is whatever the service-authorization reference (`docs.aws.amazon.com/service-authorization/latest/reference/`) declares, never the SDK client name. Check the prefix there before writing a policy; a single `elasticloadbalancing:Describe*` covers `DescribeLoadBalancers`, `DescribeListeners`, `DescribeTargetGroups`, `DescribeRules` and `DescribeListenerCertificates` for both generations.

Two verification habits that catch this class cheaply:

- An `AccessDenied` message **names the correct action** — `User … is not authorized to perform: elasticloadbalancing:DescribeLoadBalancers`. When a call fails on permissions, read the prefix the error itself reports instead of trusting the client name you invoked.
- Validating that a policy file parses as JSON proves nothing about whether its actions exist. Parse-check is syntax; `SimulatePrincipalPolicy` (needs `iam:SimulatePrincipalPolicy`), the service-authorization reference, or simply saving it in the console is semantics.
