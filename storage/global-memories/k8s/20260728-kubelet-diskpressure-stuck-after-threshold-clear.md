---
date: 2026-07-28
keywords: ["k8s", "kubelet", "diskpressure", "eviction", "k3d"]
aliases: ["stuck diskpressure", "disk-pressure taint re-added", "frozen node heartbeat"]
trigger-on: ["disk-pressure", "kubelet-eviction", "node-disk-pressure"]
---

## kubelet DiskPressure stays True after the disk frees — wait 5 minutes before restarting

In k3d clusters the kubelet keeps `DiskPressure=True`, and re-adds the `node.kubernetes.io/disk-pressure:NoSchedule` taint, after disk usage has already dropped below the hard eviction threshold. This is `evictionPressureTransitionPeriod` (default `5m0s`) working as designed: the condition clears only once the pressure has been absent for the whole period, measured from when the disk actually freed. Removing the taint by hand during that window does not hold — kubelet puts it back because the condition genuinely is still True.

**Wait out the transition period before concluding anything is stuck**, then re-check. Restart the node container (`docker restart <node-name>`) only if the condition persists well beyond it — the restart re-evaluates conditions fresh, but it is usually unnecessary and costs a control-plane restart.

Do not read a static `lastHeartbeatTime` as a frozen status loop. Node status is reported every `nodeStatusReportFrequency` (default `5m0s`) when nothing changes, even though `nodeStatusUpdateFrequency` is `10s`, so a condition timestamp several minutes old is normal. Confirm the loop is alive by sampling twice more than five minutes apart, or by checking that `Ready` advances.

The `status_manager` error `no relationship found between node X and this object` is unrelated: NodeRestriction rejecting status updates for pods no longer bound to the node, typically stale or evicted ones. It is one-off noise around an eviction event, not a symptom of a wedged kubelet.

Confirmed on the observability k3d cluster (2026-11-26), where a 4-minute-old heartbeat and a re-appearing taint were initially misread as a wedge; after the transition period elapsed the node reported `DiskPressure=False` with a heartbeat 7 seconds old and zero identity errors.
