---
date: 2026-09-27
keywords: ["docker", "tmpfs", "noexec", "go", "container"]
trigger-on: ["docker-tmpfs", "go-run-container", "compiled-binary-in-tmp"]
---

## `docker run --tmpfs` mounts default to `noexec`

A `--tmpfs /tmp` mount is created `rw,noexec,nosuid,nodev`, so a tool that writes a compiled binary into `/tmp` and executes it dies with `fork/exec …: permission denied` — the first symptom of `go run` in a hardened container, because Go builds into a cache under `/tmp`. Mount it executable: `--tmpfs /tmp:exec` (optionally `--tmpfs /tmp:exec,size=256m`). Interpreted runtimes (node, php, single-file java) never notice, because they do not exec from `/tmp` — the trap only appears the first time a compiled language runs in such a container.
