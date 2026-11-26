---
date: 2026-11-25
keywords: ["kubectl", "k8s", "delete"]
aliases: ["kubectl delete multiple resources", "services not found", "delete several kinds at once"]
trigger-on: ["kubectl-delete-multi"]
---

## `kubectl delete` takes one type per token, not type-name pairs

`kubectl delete service a serviceaccount b poddisruptionbudget c` does **not** delete three different kinds: once a type is given, every following bare name is treated as another name of that same type, so it fails with `Error from server (NotFound): services "serviceaccount" not found` — and only the first resource is actually deleted. Use the `type/name` form for a mixed list (`kubectl delete service/a serviceaccount/b poddisruptionbudget/c cronjob/d`), or issue one command per kind. The `type name type name` form only works when every resource shares the first type.
