---
date: 2026-09-15
keywords: ["docker", "docker-compose", "env_file", "secrets", "config"]
trigger-on: ["docker-compose-config-inspection", "compose-env-file"]
---

## `docker compose config` prints `env_file` secrets to stdout

Running `docker compose config` (or `config --images`, `config --services`) to validate or inspect a compose model **renders the resolved environment**, including values read from any `env_file:`. If a service declares `env_file: - .env` holding API keys, those keys are written to stdout in cleartext — and from there into a terminal transcript, CI log, or agent session log.

Treat `docker compose config` as a secret-reading command:

- Never run it on the **real** files when any selected service uses `env_file` — or redirect and discard, understanding the values were still materialised.
- To validate syntax without rendering secrets, prefer a narrow check (`docker compose config --quiet`) or validate a copy with placeholder values.
- On a shared or logged session, assume anything printed is disclosed: rotate the keys.

Also note this pairs with a subtler trap in the same area: `${VAR}` in a compose file is **interpolation**, resolved from the shell environment plus the `.env` in the compose *project* directory. With a multi-file `-f` list the project directory is the **first** `-f` file's directory, so a repo-root `.env` is silently ignored when the first `-f` points at a subdirectory — the variable interpolates to empty and `${VAR:-}` hides it. Load the file explicitly (`set -a; . ./.env; set +a`) before invoking compose if you need it.
