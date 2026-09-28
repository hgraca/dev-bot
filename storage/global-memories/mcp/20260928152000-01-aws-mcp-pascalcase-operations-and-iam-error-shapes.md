---
date: 2026-09-28
keywords: ["mcp", "aws", "iam", "python"]
trigger-on: ["aws-mcp-run-script", "aws-mcp-permissions"]
---

## The AWS MCP proxy wants PascalCase operation names, and the two failure modes mean different things

`call_boto3` on the AWS MCP server expects the API operation named as AWS spells it — `ListClusters`, `DescribeSecurityGroups` — not the boto3 snake_case method (`list_clusters`). The snake_case form returns `OperationNotFoundError`, which reads like "this server has no such API" but in fact only means the name was wrong, so do not conclude the service is unexposed from it. The two errors are worth telling apart: `OperationNotFoundError` = wrong operation name; `AccessDeniedException` = correct name, insufficient policy. A read-only identity also needs **explicit read actions per service** — one already able to call `DescribeSecurityGroups` still could not read a single MSK cluster until `kafka:ListClusters`, `kafka:DescribeCluster` and `kafka:ListNodes` were granted, and its denial arrived as `kafka:ListClusters … not authorized … no identity-based policy allows`. The denial also names the evaluated resource, which is how you learn the scoping: `List*` actions are evaluated against an account-level resource (`arn:aws:kafka:…:/v1/clusters`) so they need `Resource: "*"`, while describes and list-nodes can be scoped to the cluster ARN. Operations are also an allowlist — an operation the policy does cover still returns `OperationNotFoundError` if the proxy does not expose it.
