---
date: 2026-10-09
keywords: ["otel", "k8sclusterreceiver", "rbac", "cache-sync", "crash-loop"]
aliases: ["collector restarts every 10 minutes", "failed to start receiver", "Timed out waiting for initial cache sync"]
trigger-on: ["otel-k8s-cluster-receiver", "otel-collector-crash-loop", "k8s-informer-cache-sync"]
---

## A `k8s_cluster` receiver with incomplete informer RBAC crash-loops the collector every 10 minutes

The k8s_cluster receiver's shared informers must finish their initial cache sync or the receiver's `Start` fails. If the ServiceAccount cannot `list`/`watch` **any** watched resource, `cache.WaitForCacheSync` never returns; after a fixed **10-minute** timeout the receiver logs `Timed out waiting for initial cache sync`, reports the error to the host, and the collector logs `Asynchronous error received, terminating process` with `"error": "failed to start receiver"`, then exits cleanly (exit 0, container `lastState.reason: Completed`). The kubelet restarts it and the cycle repeats forever. The tells are a `Completed` lastState with a ~10-minute container lifetime and reflector `cannot list resource "X"` (403) lines. Trim a broad ClusterRole at your peril: a gateway ClusterRole that granted everything except `horizontalpodautoscalers` (autoscaling), `replicationcontrollers` and `resourcequotas` (core) produced 10k+ restarts over 70 days — the informer waits on the *whole* watched set, so one missing resource stalls the sync. Grant the receiver the full upstream k8sclusterreceiver resource set; `autoscaling/horizontalpodautoscalers` is the one most often forgotten.
