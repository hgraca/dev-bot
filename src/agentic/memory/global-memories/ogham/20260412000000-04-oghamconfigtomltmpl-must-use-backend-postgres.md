---
date: 2026-04-12
keywords: ["ogham", "database"]
---

## `ogham/config.toml.tmpl` must use `backend = "postgres"`

The ogham installer template must set `[database] backend = "postgres"`. Using `"supabase"` requires a separate `SUPABASE_URL` env var and will break `ogham health` even with Postgres running.
