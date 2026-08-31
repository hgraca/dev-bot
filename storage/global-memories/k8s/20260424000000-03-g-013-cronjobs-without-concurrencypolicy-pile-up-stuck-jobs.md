---
date: 2026-04-24
keywords: ["k8s"]
---

## G-013: CronJobs without concurrencyPolicy pile up stuck Jobs

- **Problem**: Default `concurrencyPolicy: Allow` creates a new Job every schedule tick (`* * * * *`) even if the previous Job's pod can't schedule. When the autoscaler is down and all nodes are at max pod count, this creates dozens of Pending pods per CronJob.
  Set `concurrencyPolicy: Forbid` on all CronJobs. Also suspend CronJobs when the autoscaler is known to be broken to prevent any new Jobs.
