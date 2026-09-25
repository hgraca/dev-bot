---
date: 2026-09-24
keywords: ["signoz", "saved-views", "migration", "data-loss", "0.137"]
trigger-on: ["signoz-upgrade", "signoz-saved-views-migration"]
---

## The v0.137 saved-view repair resets unreadable fields to their empty defaults

SigNoz v0.137.0 converts saved views to a typed schema, and the guide warns that a view whose stored spec has unreadable fields is repaired by resetting each bad field to its empty default (a view that still cannot be parsed is deleted). The practical consequence is quieter than "deleted": the view **survives but loses its queries** — `GET /api/v2/saved_views/{id}` comes back with `spec.queries: []` and `spec.selectedFields: []`, so it looks present and usable while returning everything. Re-exporting it and posting it straight back fails with `400 at least one query is required`, because there is no round-trip to copy: the pre-migration definition is the only surviving copy. `name` is immutable, so re-importing a corrected definition **creates a new view** beside the empty one rather than fixing it — the emptied views must be deleted deliberately.
