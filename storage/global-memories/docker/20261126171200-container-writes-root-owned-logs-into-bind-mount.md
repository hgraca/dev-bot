---
date: 2026-11-26
keywords: ["docker", "root-owned", "bind-mount", "disk-full", "laravel"]
aliases: ["container writes files as root", "runaway log", "27GB per hour"]
trigger-on: ["docker-bind-mount-root-uid", "container-log-runaway"]
---

## A container that bind-mounts a worktree writes root-owned logs the host user cannot truncate

When a dev container runs as root and bind-mounts a project directory, anything it writes lands as `root:root` on the host — including `storage/logs/laravel.log`. Two consequences: the host user cannot truncate the file (no write permission), and `rm` fails too because the containing `storage/logs/` directory is also root-owned, so unlink permission is missing. A single runaway process is enough to fill a disk: a `rector --dry-run` that entered infinite Symfony-Console recursion appended a stack trace per iteration and wrote ~27 GB/h into a worktree's log until it was killed. Triage: `find ~ -xdev -type f -mmin -360 -size +200M -printf '%TT %10s %p\n'` finds the churn source fast (a depth-limited `du` misses it — the file sits deep inside a large tree), two `stat -c %s` samples give the growth rate, and `lsof +L1` finds space held by deleted-but-open files. Order matters: kill the writer first (truncating while it appends is futile), then empty the file from a root context, e.g. `docker run --rm -v <worktree>:/app <image> sh -c ': > /app/storage/logs/laravel.log'`.
