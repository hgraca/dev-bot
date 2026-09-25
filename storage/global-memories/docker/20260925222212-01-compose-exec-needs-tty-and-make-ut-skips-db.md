---
date: 2026-09-25
keywords: ["docker", "docker-compose", "make", "tty"]
trigger-on: ["docker-compose-exec-tty"]
---

## `docker compose exec` needs a TTY on stdin — never wire `/dev/null` into it

Make targets that route through `docker compose exec --user … <service> …` fail with `cannot attach stdin to a TTY-enabled container because stdin is not a terminal` when stdin is not a terminal. The general hardening advice to redirect stdin from `/dev/null` is actively wrong here: run the target in a PTY (which supplies a real TTY) and pass no stdin redirect at all. A second trap in the same suites — a `make ut` documented as "without setting up DBs" does **not** create the test database, so on a fresh environment it dies with `SQLSTATE[HY000] [1049] Unknown database 'phpunit'` and hundreds of errors that look like a code failure; use the bootstrap target (`make unit`, `make test`) when verifying a change from cold. Third: `docker compose exec` inherits the _container's_ environment, so make variables given on the command line do not reliably reach the inner make — prefer a `run`-style target that takes the whole command as one argument (`make run CMD="…"`).
