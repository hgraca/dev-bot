---
date: 2026-10-09
keywords: ["otel", "hostmetrics", "filesystem", "root_path", "k3d"]
aliases: ["hostmetrics disk usage missing", "system.filesystem empty", "root_path reports nothing", "host disk usage blank"]
trigger-on: ["otel-hostmetrics-filesystem", "otel-collector-container-mount", "otel-hostmetrics-root-path"]
supersedes: ["otel/20260615131100-root-path-partial-mounts-cause-filesystem-scraper-errors.md"]
---

## The hostmetrics filesystem scraper needs the FULL host root mounted — deleting `root_path` is not the fix

When the hostmetrics receiver runs in a container, `filesystem: {}` emits nothing unless the host root is reachable: the scraper reads `<root_path>/proc/1/mountinfo` and then `statfs`-es each mountpoint under `root_path`, so mounting only `/proc`,`/sys`,`/dev` at `/hostfs/...` makes it error (`no such file or directory`) on every path outside them. The two halves travel together — bind-mount the host `/` read-only at `/hostfs` (with `mountPropagation: HostToContainer`) **and** set `root_path: /hostfs`. Do not "fix" the errors by deleting `root_path`: the scraper then sees only the container's own mounts (overlay/tmpfs/proc/sysfs), which its default exclude list drops, so `system.filesystem.*` stays empty and the SigNoz Infrastructure → Hosts disk column shows nothing (cpu/memory/disk-io/network keep working — they read the shared `/proc`). On k3d the nodes are themselves containers, so the node root is an `overlay` mount that the default excludes drop even with the full mount: add `include_virtual_filesystems: true` and `include_mount_points: {mount_points: ["/"], match_type: strict}` to keep it to the node root (whose `statfs` reflects the underlying host disk) while excluding the per-pod overlay flood. This supersedes `otel/20260615131100-root-path-partial-mounts-cause-filesystem-scraper-errors.md`, whose "remove `root_path`" remedy silently yields no data.
