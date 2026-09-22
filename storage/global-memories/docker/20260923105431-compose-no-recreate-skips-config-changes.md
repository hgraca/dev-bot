---
date: 2026-09-23
keywords: ["docker", "docker-compose", "no-recreate", "bind-mount"]
trigger-on: ["docker-compose-shared-project", "compose-config-drift-reconcile"]
---

## compose `up --no-recreate` silently applies no config change to an existing container

With `docker compose up -d --no-recreate`, compose recreates a container only when its **image id** changes or the container does not exist yet. A change to the compose **config** — a bind-mount source, a port, an environment value — is silently not applied: `up` reports success while the running container keeps its creation-time settings. Docker fixes mounts at container creation (there is no live attach), so this bites hardest on a configurable root mount. Applying the change needs an explicit recreate: `docker compose -f <file> up -d --force-recreate <service>`. A recreate is not a removal — named volumes survive it — so it is the right tool when a full teardown would be too broad (e.g. when the containers are shared and other consumers are live). The pattern that keeps it from being a manual step: detect the drift on `up` (read `docker inspect <cid> --format '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}}{{end}}{{end}}'` and compare it with the desired value) and `--force-recreate` only on a mismatch.
