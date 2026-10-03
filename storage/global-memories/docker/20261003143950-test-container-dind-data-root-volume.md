---
date: 2026-10-03
keywords: ["docker", "docker-in-docker", "overlayfs", "volume", "test-container"]
trigger-on: ["docker-in-docker", "nested-dockerd", "test-container-daemon"]
---

## Nested dockerd needs a data-root volume, and `docker rm -f` leaks it without `-v`

Running a real `dockerd` inside a `--privileged` test container (Docker-in-Docker) hits two non-obvious traps. First, the container image's own root is overlayfs, so the inner daemon's default `/var/lib/docker` sits on an overlay backing: `dockerd` starts and `docker info` succeeds, but `docker run` fails with `failed to mount … fstype: overlay … invalid argument`. Give the inner daemon a data-root on a non-overlay filesystem by mounting an anonymous volume at `/var/lib/docker` (`docker run --privileged --mount type=volume,dst=/var/lib/docker`); the volume lives on the host's real filesystem, so nested overlay2 works (verified in dev-bot's `devbot-test` image, dockerd 29.1.3, inner `docker run alpine` succeeds). Second, `docker rm -f <name>` does NOT remove that anonymous volume — `--rm` cleans anonymous volumes only on a natural exit, so a launcher that force-kills a still-running container leaks the inner daemon's entire data-root (its images and containers); always `docker rm -f -v <name>` (verified: dangling-volume count 260 → 261 after a force kill without `-v`). Start `dockerd` through the non-root user's NOPASSWD sudo, wait for `/var/run/docker.sock` to appear, then `chmod 666` it — the run user is not in the docker group without a re-login, and polling `docker info` before the chmod just spins.
