---
date: 2026-04-12
keywords: ["docker", "container"]
---

## `docker ps | grep` fails in pipefail subshells

`docker ps | grep -q "container-name"` can silently fail in `set -euo pipefail` subshells when `docker ps` output has very long lines that get truncated by the pipe buffer.
Fix: always use `docker ps --format '{{.Names}}' | grep -q "^container-name$"` for exact name matching.
