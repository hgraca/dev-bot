---
date: 2026-04-19
keywords: ["ogham", "mcp"]
---

## Ogham hybrid_search_memories function signature mismatch after upgrades

When ogham-mcp is upgraded (e.g. to v0.10.3) but DB migrations aren't applied, the Postgres function `hybrid_search_memories` has an old 10-parameter signature while the new code expects 12 parameters (added `query_entity_tags` and `recency_decay`). `ogham init --skip-clients` fails with "type relationship_type already exists" on partial schemas. Fix: apply the updated function manually from the installed schema file at `~/.local/share/uv/tools/ogham-mcp/...`, then run pending numbered migrations (e.g. `021_dim_aware_halfvec.sql`, `022_profile_health_stats.sql`).
