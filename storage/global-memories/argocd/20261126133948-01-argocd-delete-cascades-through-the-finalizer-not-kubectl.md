---
date: 2026-11-26
keywords: ["argocd", "cascade", "orphan", "finalizer", "preserveResourcesOnDeletion"]
aliases: ["cascade=orphan", "delete application without deleting resources", "resources-finalizer"]
---

## `kubectl delete app --cascade=orphan` does not spare an Application's resources

`--cascade=orphan` sets a propagation policy that governs **ownerReferences** garbage collection. Argo CD does not delete an Application's managed resources through ownerReferences — the workloads, Services and CRDs it manages carry none — it deletes them from the Application's own `resources-finalizer.argocd.argoproj.io` finalizer, which runs whatever the propagation policy says. So `kubectl delete application X --cascade=orphan` still deletes everything X manages. The documented non-cascading delete strips the finalizer first:

```
kubectl patch app <name> -n argocd -p '{"metadata":{"finalizers":null}}' --type merge
kubectl delete app <name> -n argocd
```

Deleting an **ApplicationSet** is the opposite case and the confusion is worth separating: its generated Applications *do* carry an ownerReference to it, so `kubectl delete applicationset <name> --cascade=orphan` genuinely leaves them running (and managed by nothing until a new set adopts them by name).

`spec.syncPolicy.preserveResourcesOnDeletion: true` is the other half: generated Applications are then created *without* the resources finalizer, so deleting one cannot delete what it manages. Setting that flag on an ApplicationSet that lacked it **removes** the finalizer from the Applications it already generated — verified in the GET-E prod cluster on 2026-11-25, where `kube-state-metrics`, `mysqld-exporter`, `rds-cloudwatch-exporter`, `redis-exporter` and `signoz-k8s-infra` lost it on the next reconcile. Always check `kubectl -n argocd get applications -o custom-columns=NAME:.metadata.name,FIN:.metadata.finalizers` before deleting an Application whose graph includes CRDs: a cascading delete of a CRD chart takes every custom resource of that kind — for a Gateway, that is the load balancer.
