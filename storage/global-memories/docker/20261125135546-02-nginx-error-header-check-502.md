---
date: 2026-11-25
keywords: ["docker", "nginx", "security-headers", "ci"]
aliases: ["add_header always check", "error response header probe", "502 header stand-in"]
trigger-on: ["nginx-header-check", "docker-run-upstream-stub"]
---

## Probe nginx error-response headers without the app

`add_header` without `always` sends the directives on 2xx/3xx only, so a probe that checks a single 200 reports a false pass. A CI check can build the production nginx image, run it with the backend hostname mapped to `127.0.0.1`, and request a static file (200) plus a missing path — `try_files` falls through to the refused upstream and returns 502 — then require both responses to carry the same header set. That exercises the real server-level inheritance without a database or app container, and it fails when `always` is removed. Publish the container on a random host port (`-p 127.0.0.1::80` then `docker port`) to avoid collisions.
