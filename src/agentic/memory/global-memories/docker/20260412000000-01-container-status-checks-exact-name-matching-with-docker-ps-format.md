---
date: 2026-04-12
keywords: ["docker", "container"]
---

## Container status checks: exact name matching with `docker ps --format`

All container presence checks must use `docker ps --format '{{.Names}}'` and anchor the grep pattern (`^name$`) to avoid false positives from partial name matches and false negatives from truncated output. Apply in `--status` checks and anywhere container existence is tested.
