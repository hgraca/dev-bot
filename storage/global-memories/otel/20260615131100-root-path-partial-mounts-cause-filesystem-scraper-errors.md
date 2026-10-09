---
date: 2026-06-15
keywords: ["otel", "hostmetrics", "root_path", "filesystem"]
superseded_by: ["otel/20261009093307-hostmetrics-filesystem-needs-the-full-host-root.md"]
---

> **Superseded by** `otel/20261009093307-hostmetrics-filesystem-needs-the-full-host-root.md` (2026-10-09) — deleting `root_path` leaves `system.filesystem.*` empty (the container-view mounts are all in the scraper's default exclude list). The correct fix is to mount the FULL host root at `/hostfs` and keep `root_path`.

When `hostmetrics::root_path: /hostfs` is set in the OTel collector config, the filesystem scraper walks paths from that root (e.g. `/hostfs/var/lib/...`). If the DaemonSet only mounts host `/proc`, `/sys`, `/dev` as hostPath volumes into `/hostfs/proc`, `/hostfs/sys`, `/hostfs/dev`, any path outside those subtrees fails with "no such file or directory". The fix is to remove `root_path` entirely — containers in Kubernetes share the host kernel /proc by default, so the hostmetrics scrapers work without explicit mounts or root_path. This matches the simpler OTel reference patterns used by upstream distributions.

When `hostmetrics` receiver has `root_path: /hostfs` and only /proc, /sys, /dev are mounted as hostPath volumes (not the full root `/`), the `filesystem` scraper fails with "no such file or directory" for paths outside the mounted subtrees (e.g. `/hostfs/var/lib/kubelet/...`). The scraper expects the full host filesystem tree under `root_path`.

Fix: remove `root_path` entirely. In Kubernetes, containers share the host kernel's `/proc` by default, so `cpu`, `memory`, `disk`, `load`, `network` scrapers work without any hostPath mounts. The `filesystem` scraper will report container-view mounts (limited but functional). Both the OTel Demo producer collector and staging collector reference implementations do not use `root_path`.
