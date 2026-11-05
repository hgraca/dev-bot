---
date: 2026-11-05
keywords: ["aws", "iam", "cloudwatch", "kafka", "resource-arn"]
aliases: ["AccessDenied GetMetricData", "DescribeClusterOperation AccessDenied", "CloudWatch read policy"]
trigger-on: ["aws-iam-policy", "cloudwatch-read"]
---

## CloudWatch metric reads and kafka:DescribeClusterOperation require Resource "*"

`cloudwatch:GetMetricData`, `cloudwatch:GetMetricStatistics` and `cloudwatch:ListMetrics` do not support resource-level permissions — a policy that scopes them to a specific resource yields `AccessDenied`. Grant all three on `"Resource": "*"`. Separately, `kafka:DescribeClusterOperation` authorizes against an operations ARN of the shape `arn:aws:kafka:<region>:<account>:/v1/operations/<url-encoded-operation-arn>`, which a cluster-scoped `arn:aws:kafka:...:cluster/...` resource never matches; it also needs `"Resource": "*"`. The symptom is identical for both: `AccessDenied`/`AccessDeniedException` naming only the one action, while sibling reads (`kafka:ListClusterOperations`, `kafka:ListNodes`, `kafka:ListClustersV2`) succeed — which reads as a broken tool rather than a missing permission.
