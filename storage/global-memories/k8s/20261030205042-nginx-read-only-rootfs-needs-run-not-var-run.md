---
date: 2026-10-30
keywords: ["k8s", "nginx", "read-only-rootfs", "runAsNonRoot", "emptyDir"]
aliases: ["nginx non-root crash", "nginx pid permission denied", "read-only root filesystem nginx"]
trigger-on: ["nginx-unprivileged-container", "read-only-root-filesystem"]
---

## An unprivileged nginx on a read-only root filesystem must mount /run, not /var/run

Running `nginx:alpine` as uid 101 with `readOnlyRootFilesystem: true` fails at start-up with
`open() "/run/nginx.pid" failed (13: Permission denied)` unless every path nginx writes is backed by
a volume. The image's nginx.conf writes the pid to `/run/nginx.pid`, and `/var/run` is a symlink to
`../run`, so an emptyDir mounted at `/var/run` does not cover `/run` — mount `/run` itself. The full
writable set is `/run` (pid), `/var/cache/nginx` (temp and proxy dirs) and `/tmp`. A non-root process
also cannot bind port 80, so the server block listens on 8080 and the Service keeps the external
contract with `port: 80 → targetPort: 8080`. Set `fsGroup` to the runtime uid so the emptyDirs are
writable, and expect one harmless `the "user" directive ... ignored` warning. Verified by running the
exact securityContext and volume layout in Docker: the container started and answered 401 on 8080.
