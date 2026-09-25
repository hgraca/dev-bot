---
date: 2026-09-24
keywords: ["k8s", "k3d", "storage", "backup", "permissions"]
trigger-on: ["k3d-backup", "k3d-storage-snapshot"]
---

## Read k3d bind-mounted storage through the node container, not the host

A k3d cluster bind-mounts host paths into its node containers, and the directories a workload creates there are owned by the image's user with restrictive modes — ClickHouse writes `access/`, `data/`, `flags/` and `metadata/` as mode `2750` owned by its in-image user, so the host user cannot even search them and a host-side `cp -a` fails partway. Escalating to `sudo cp -a` inside an automation script is the trap: it blocks on a password prompt and, worse, a partially-completed copy leaves a directory that a `[ -d ]` test accepts as a backup. Read the data through the **node container** instead — `docker exec k3d-<cluster>-server-0 tar -cf - -C /var/lib/rancher/k3s/storage/<path> . > snapshot.tar` — which runs as root and needs no host privilege; the reverse (`docker exec -i … tar -xf -`) restores the same way. Write the archive as a single file so an empty or truncated result is detectable (`[ -s ]`), and prefer a tar over a directory copy for that reason.
