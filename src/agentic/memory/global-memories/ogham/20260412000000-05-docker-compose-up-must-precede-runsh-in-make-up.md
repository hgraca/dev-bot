---
date: 2026-04-12
keywords: ["ogham"]
---

## `docker compose up` must precede `run.sh` in `make up`

The installer (`bin/install.sh`) runs health checks (e.g. `ogham health`) that require the Postgres and Ollama containers to already be running. Always start `docker compose up -d` **before** calling `bin/install.sh`.
