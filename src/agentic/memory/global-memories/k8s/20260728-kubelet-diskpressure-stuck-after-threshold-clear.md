---
date: 2026-07-28
keywords: ["k8s", "kubelet", "diskpressure", "eviction", "k3d"]
trigger-on: ["disk-pressure", "kubelet-eviction", "node-disk-pressure"]
---

## kubelet DiskPressure condition stays True even after disk goes below eviction threshold

In k3d clusters, the kubelet may not clear its DiskPressure condition even after disk usage drops below the hard eviction threshold (5%). This happens because the kubelet uses an internal transition period (`evictionPressureTransitionPeriod: 5m0s`) and may lose the monitoring signal. The fix is to restart the k3d node container: `docker restart <node-name>`. After restart, the kubelet re-evaluates conditions fresh and clears the taint. Also check `evictionPressureTransitionPeriod` in kubelet config — the condition requires disk to stay below threshold for the full period before clearing.
