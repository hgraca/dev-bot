---
date: 2026-10-29
keywords: ["k8s", "eks", "access-entry", "iam", "authenticationMode"]
trigger-on: ["eks-access-entries"]
---

## EKS access-entry introspection is scoped to the access-entry ARN, not the cluster ARN

Scoping `eks:DescribeAccessEntry` or `eks:ListAssociatedAccessPolicies` to `arn:aws:eks:<region>:<account>:cluster/<name>` yields `AccessDenied` even though the action is otherwise allowed: those two evaluate against `arn:aws:eks:<region>:<account>:access-entry/<cluster>/<type>/<account>/<principal>/<uuid>`. Only `eks:ListAccessEntries` takes the cluster ARN. Allow `.../access-entry/<cluster>/*` and keep `ListAccessEntries` on the cluster ARN. Related trap: access entries need `authenticationMode` `API` or `API_AND_CONFIG_MAP` (the switch is one-way). In `CONFIG_MAP` mode `ListAccessEntries` fails with `InvalidRequestException ... must be set to one of [API, API_AND_CONFIG_MAP]` — that message, not `AccessDenied`, is the tell that the mode is the blocker. Entries can already exist while the mode is `CONFIG_MAP`; they are simply dormant.
