---
date: 2026-04-24
keywords: ["k8s", "kubectl", "cluster"]
---

## M-FLOW-007: Suspend CronJobs when autoscaler is broken

CronJobs with `* * * * *` schedule kept spawning Pending pods every minute while the autoscaler was down for 42 days. Even with `concurrencyPolicy: Forbid`, one stuck Pending Job per CronJob wastes pod slots.
When the autoscaler is confirmed broken: (1) add `concurrencyPolicy: Forbid` to prevent pile-up, (2) suspend CronJobs via `kubectl patch cronjob <name> -p '{"spec":{"suspend":true}}'` to stop new Jobs entirely, (3) delete existing stuck Jobs. Unsuspend after the autoscaler is fixed.
