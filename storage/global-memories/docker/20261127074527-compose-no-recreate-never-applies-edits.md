---
date: 2026-11-27
keywords: ["docker", "docker-compose", "no-recreate", "drift"]
aliases: ["compose config hash", "gateway reconcile", "stale container config"]
trigger-on: ["compose-no-recreate-drift", "gateway-config-reconcile"]
---

## A compose service started with `--no-recreate` never picks up an edit, so reconcile it explicitly

`docker compose up -d --no-recreate` is what keeps a shared dev stack from restarting on every
bring-up, and it also means a changed `healthcheck`, `command`, `image` or bind mount reaches the
container **never** — Docker fixes all of them at creation. The symptom is silent: the container
stays healthy and keeps serving the old configuration while the file on disk says otherwise.

Reconcile it from the module's own script, comparing what the container was created from with what
the file says now. Two findings worth keeping:

- **`docker compose config --hash <service>` is not comparable across file sets.** A container
  created by a merged multi-`-f` project (a pre-existing `com.docker.compose.config-hash` label)
  never matches the hash computed from the module's single `-f` file, so a naive comparison
  recreates the service on every start.
- **A fingerprint recorded after each successful creation avoids that and covers every property.**
  Hash the compose file plus the interpolated mount root, write it beside the container's data, and
  recreate when it differs. `docker inspect`-per-field comparisons always miss the next property
  someone adds.
- **Adopt a container that is newer than the file.** `docker inspect -f '{{.Created}}'` beats the
  file's mtime ⇒ compose created it seconds ago during this same up; record the fingerprint instead
  of recreating a healthy container on every clean start.

A failed recreate must return non-zero from the module script: a caller that only warns leaves a
stale gateway that still answers its readiness probe, and the start gets recorded as complete.
