---
date: 2026-09-15
keywords: ["docker", "docker-compose", "build", "dockerfile", "no-recreate"]
trigger-on: ["compose-build-staleness", "dockerfile-change-not-applied"]
---

## A changed Dockerfile does not reach an existing image — compose only builds when the image is missing

`docker compose up` builds a `build:` service **only when its image does not exist**. Once an image is present, editing the `Dockerfile` changes nothing: no rebuild happens, silently. Adding `--build` does not help on its own either, because `--no-recreate` prevents compose from replacing a running container with the newly built image — so even a successful rebuild leaves the old container running.

Two ways out:

1. Rebuild and recreate in one step, scoped to what actually changed — build, compare the image id, recreate only if it differs:

```sh
before=$(docker image inspect "$IMAGE" --format '{{.Id}}' 2>/dev/null || true)
docker compose -f "$COMPOSE" build >/dev/null 2>&1 || exit 1
after=$(docker image inspect "$IMAGE" --format '{{.Id}}' 2>/dev/null || true)
[ "$before" = "$after" ] || docker compose -f "$COMPOSE" up -d --force-recreate
```

A cache-warm build is cheap (sub-second for a small image), so this is safe to run on every start: an unchanged build yields the same id and nothing restarts.

2. Drop `--no-recreate` and let compose reconcile, which recreates containers whose service definition or image changed. Simpler, but it re-evaluates every service — a much wider behavioural change if `--no-recreate` was deliberate.

Validation habit: after any `Dockerfile` edit, confirm the running container actually has the new content (`docker inspect <c> --format '{{.Config.Env}}'`, or a file the build added) rather than trusting that the build ran.
