---
date: 2026-09-29
keywords: ["k8s", "statefulset", "orderedready", "rolling-update", "pending"]
trigger-on: ["statefulset-template-update", "statefulset-rolled-out-stuck", "statefulset-orderedready"]
---

## A StatefulSet under the default `OrderedReady` policy will not roll its template while a pod is unhealthy — delete the stuck pod

Changing a StatefulSet's pod template with `updateStrategy: RollingUpdate` + `partition: 0` bumps `status.updateRevision` immediately, so the object looks updated and `updateRevision != currentRevision`. But under the default `podManagementPolicy: OrderedReady` the controller only recreates pods that are **Running and Ready** before proceeding, so a pod stuck `Pending` — unschedulable because of a stale `required` anti-affinity, a missing AZ-matching node, or exhausted capacity — **blocks its own replacement**. The template change lands on the StatefulSet object and nowhere else: the old unschedulable pod is never deleted, the workload stays down, and it looks as though the manifest fix had no effect. The remedy is to delete the stuck pod directly; the controller recreates it from `updateRevision` (which already carries the new template) and the replacement schedules normally. Annotating the pod does **not** reliably force the scheduler to retry — a freshly created pod from deletion does, because scheduling is attempted at creation. A separate bound PVC is untouched by deleting the pod, so stateful data is safe.
