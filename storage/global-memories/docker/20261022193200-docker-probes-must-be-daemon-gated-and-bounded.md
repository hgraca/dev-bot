---
date: 2026-10-22
keywords: ["docker", "image-inspect", "daemon", "timeout"]
aliases: ["image absent vs daemon down", "wedged docker socket", "bounded probe"]
trigger-on: ["docker-image-probe", "docker-daemon-preflight"]
---

## Docker probes must be daemon-gated and bounded

`docker image inspect` exits non-zero for two different situations: the image is absent, and the
daemon is unreachable or the socket is denied. Treating any failure as "image missing" makes a script
announce a download that cannot happen and buries the real infrastructure error — the message arrives
just before compose fails for an unrelated reason. Probe `docker info` first and stay silent when it
fails; only then treat a failing inspect as an absent image.

Bound both probes as well. A wedged socket blocks forever, and GNU `timeout` is absent on macOS, so
the portable form is a bash watchdog: start the command in the background and poll `kill -0` against
a deadline, kill on expiry, and return a sentinel (`124`) that callers treat as *inconclusive* —
never as "absent". `bin/update.sh`'s tag fetch and `datasources/up.sh`'s `_docker_bounded` are the
two dev-bot instances of the pattern. Python callers should go through a `_run(args, timeout=...)`
helper that returns `None` on `subprocess.TimeoutExpired`, so the timeout is a value the caller must
handle rather than an exception.
