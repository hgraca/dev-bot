---
date: 2026-10-14
keywords: ["k8s", "k3d", "disk-pressure", "kubelet", "eviction"]
aliases: ["node.kubernetes.io/disk-pressure", "shared host disk k3d", "imagegc freed 0 bytes"]
trigger-on: ["k3d-disk-pressure", "kubelet-eviction-debugging"]
---

## k3d nodes share the host disk, and kubelet holds DiskPressure for five minutes

Three facts cost real time when a k3d cluster evicts pods for "disk pressure". Every k3d node reports the same `node.fs` because all nodes are containers on one Docker host sharing one backing filesystem — identical `node.fs.usedBytes` and `availableBytes` across nodes is one disk, not a coincidence, so the fix is to free space on the host rather than "on a node". The kubelet summary API exposes the real bytes without a shell or a scheduled pod (`kubectl get --raw /api/v1/nodes/<name>/proxy/stats/summary`, read `node.fs.*` and `node.runtime.imageFs.*`); when `imageFs` is small but `node.fs` is full the consumer is not container images, and the tell is kubelet logging that deleting unused images freed 0 bytes. Finally, kubelet holds a pressure condition until it has been absent for `eviction-pressure-transition-period` (default 5 minutes), so after freeing space `DiskPressure` stays `True` and the `node.kubernetes.io/disk-pressure:NoSchedule` taint stays applied for about five minutes before the node recovers and pods reschedule — do not conclude the fix failed before then.
