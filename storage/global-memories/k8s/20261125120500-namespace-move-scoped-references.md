---
date: 2026-11-25
keywords: ["k8s", "namespace-move", "Gateway", "allowedRoutes", "ExternalSecret", "SecretStore"]
aliases: ["cross-namespace route", "SecretStoreNotFound", "Same namespace listener"]
trigger-on: ["gateway-allowed-routes", "externalsecret-namespace-move"]
---

## Moving a workload to a new namespace breaks the references that carry no namespace

Two namespaced references have no namespace field, so a directory move to a new namespace fails silently rather than at apply time. An `ExternalSecret` with `secretStoreRef: {kind: SecretStore, name: main-store}` resolves that store **in its own namespace** — in the new namespace it fails with `SecretStoreNotFound`, no Secret is created, and the pods sit in `CreateContainerConfigError` (`kind: ClusterSecretStore` has no such problem). A Gateway listener with `allowedRoutes.namespaces.from: Same` accepts HTTPRoutes only from the Gateway's own namespace: routes in the new namespace get `Accepted: False` while the old routes keep serving, so the move looks successful until the old routes are deleted — at which point the hostname loses every backend. Both are cutover traps, not apply errors. When a staging move "just works", check whether staging's Gateway uses a namespace `Selector` and whether its secrets were copied by hand; production may be configured the other way. Also suspend old CronJobs before an overlap: a `* * * * *` schedule in both namespaces runs every job twice until the old set is removed.
