---
date: 2026-09-22
keywords: ["docker", "virtiofs", "bind-mount", "chmod", "docker-desktop-macos"]
trigger-on: ["docker-bind-mount-chmod", "container-owns-state-dir", "virtiofs-ownership"]
---

## On Docker Desktop macOS a container chmod rewrites the bind mount's host ownership to 0:0

A container `chmod()` on a host bind-mounted directory is emulated by Docker Desktop's virtiofs by writing `user.containers.override_stat: <uid>:<gid>:<mode>` on the host path — and the uid:gid it writes is **always `0:0`**, whatever uid the container runs as. Verified: `docker run -u 0:0`, `-u 501:20` and `-u 1000:1000`, each running `chmod 700 /x` inside, all left `user.containers.override_stat: 0:0:040700` behind, and the container still _read_ the real host uid (`501:20`) until something chmodded it. So a service that (a) runs as a non-root host uid, (b) must own a bind-mounted state directory, and (c) chmods that directory at startup poisons itself permanently: the chmod makes the directory read back as root-owned, its ownership check fails, and every later start rewrites the same value — clearing the xattr by hand or forcing it to the correct value does not stick. Two ways out. Run the container as `0:0` so its euid agrees with what the emulation writes (but note a _pristine_ non-root-owned directory then fails the check before the chmod ever runs, so the override has to be pre-set to agree). Or take the directory off the bind mount entirely: a Docker named volume lives on the VM's own filesystem, where chmod is a real syscall. For the second, the volume's owner cannot be baked into the image — the host uid is only known at runtime — so start the container as root, `chown` the volume, then drop with `setpriv` (util-linux, already present in `node:22-slim`).
