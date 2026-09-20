---
date: 2026-09-18
keywords: ["docker", "docker-exec", "grep", "diagnosis"]
trigger-on: ["docker-exec", "container-diagnostics"]
---

## `docker exec <cmd> | grep <pattern>` returning nothing may mean the binary does not exist

If the container image lacks the command — a rebuilt slim image without `ps`, for instance — `docker exec` fails with `executable file not found in $PATH` on stderr. Piping through `2>&1 | grep <pattern>` discards that message because it matches nothing, leaving empty output that reads as "no results at all". This produced a false conclusion that a hung process had exited, when in fact the probe never ran. Check the exec's exit status, or run the probe alone before piping it, and prefer `docker top` for process inspection since it executes on the host and works regardless of what the container ships.
