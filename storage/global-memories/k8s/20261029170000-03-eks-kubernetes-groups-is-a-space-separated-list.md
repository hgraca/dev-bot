---
date: 2026-10-29
keywords: ["k8s", "eks", "kubernetes-groups", "access-entry", "aws-cli"]
trigger-on: ["eks-access-entries"]
---

## `--kubernetes-groups` takes a space-separated list, and update replaces it

`aws eks update-access-entry --kubernetes-groups a,b` fails with `The kubernetes group name a,b is invalid, it can contain alphanumeric character ...` — the parameter is a CLI list, so a comma-separated value arrives as one literal group name. Pass `--kubernetes-groups group-one group-two` (or a JSON array `'["group-one","group-two"]'`). `update-access-entry` replaces the whole list rather than appending, so adding a second group without repeating the first silently removes read access for every principal mapped to that entry.
