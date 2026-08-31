---
date: 2026-07-28
keywords: ["docker", "k3d", "container", "restart"]
trigger-on: ["k3d-container-restart", "docker-restart-error", "cannot-restart-container"]
---

## k3d node container may fail to restart with "tried to kill container, but did not receive an exit event"

When a k3d node container has been evicting pods due to disk pressure or is in a degraded state, `docker restart <node>` may fail with "tried to kill container, but did not receive an exit event". The container process is stuck and won't respond to SIGTERM. Fix: force kill with `docker kill <node>` then `docker start <node>`. This is safe for agent nodes but disruptive for the control-plane node (restart the whole container instead). After restart, the kubelet re-evaluates conditions and clears stuck taints.
