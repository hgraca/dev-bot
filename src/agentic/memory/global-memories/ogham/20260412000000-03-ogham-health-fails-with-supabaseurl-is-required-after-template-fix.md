---
date: 2026-04-12
keywords: ["ogham", "database"]
---

## `ogham health` fails with `SUPABASE_URL is required` after template fix

If `~/.config/ogham/config.toml` was written with `DATABASE_BACKEND = "supabase"` (from a stale run before the template was corrected), `ogham health` fails validation even though Postgres is running fine. Self-heals when `make up` re-runs `ogham/install.sh` and overwrites the config. Not a code bug — a one-time machine-state issue.
