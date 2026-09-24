---
date: 2026-09-24
keywords: ["docker", "container", "file-ownership", "uid"]
trigger-on: ["container-creates-new-path", "root-owned-output-file"]
---

## Run the container as the invoking user when the tool creates new paths

A container writing into a bind-mounted host tree takes the identity of what it touches: overwriting an existing file preserves the host owner, but every **new** path is created as `root:root` (mode 644), leaving the caller unable to edit their own output. Tools that move or create files hit this — ts-morph's `SourceFile.move()` implements a move as write-then-delete, so its destination is a new file (measured: `herberto:herberto 664` in, `root:root 644` out), while rope's OS-level rename keeps the same inode and the owner. Fix: `docker run --user "$(id -u):$(id -g)"` — the bind mount is host-owned so writes succeed, and read-only volumes (a scratch `node_modules`, the driver script) stay readable. It is harmless on macOS Docker Desktop, which presents host ownership regardless. Assert ownership in tests with `test -O <path>` (POSIX), not `stat -c`, which is GNU-only.
