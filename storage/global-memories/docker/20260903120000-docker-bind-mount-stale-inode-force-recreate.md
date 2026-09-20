---
date: 2026-09-03
keywords: ["docker", "bind-mount", "inode", "stale", "force-recreate"]
trigger-on: ["docker-bind-mount-stale", "docker-compose-force-recreate"]
---

## Docker bind mounts pin the source inode — a replaced host dir leaves a stale, empty mount that only --force-recreate fixes

Docker bind mounts resolve the host path to its inode at container creation and keep it forever. If the host directory is deleted and recreated (e.g. a tool like `qmd pull` or a script `rm -rf` + `mkdir` the cache dir), a running container keeps serving the orphaned — now empty — directory. Symptom is deceptive: the mount _exists_, is _empty_, and downstream tools fail with errors that look unrelated (observed: ollama `ollama create` on a Modelfile `FROM /mount/file.gguf` cannot open the file, falls back to parsing the path as a model name and returns `400 Bad Request: invalid model name`).

Two traps compound it: (1) guards that only check the mount directory exists (`docker exec c sh -c "test -d /mnt"`) pass — an empty dir is still a dir; check that a _file you expect_ is readable inside the container instead. (2) `docker compose up -d` will NOT recreate the container when the compose spec still matches the running container — it reports "up to date" — because the stale inode is invisible to compose's config-drift detection. Only `docker compose up -d --force-recreate <svc>` re-resolves the bind to the current host directory. Recovery: force-recreate, then re-verify the expected file is visible. Models/data living in a separate rw bind (e.g. `storage/ollama`) survive the recreate untouched.
