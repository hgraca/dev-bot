---
date: 2026-09-24
keywords: ["signoz", "v2-api", "dashboard", "saved-views", "legacy"]
trigger-on: ["signoz-dashboard-import", "signoz-saved-view-api", "signoz-dashboard-migration"]
---

## SigNoz V2 dashboard and saved-view CRUD semantics (verified against production)

**Dashboards.** `POST /api/v2/dashboards` requires a top-level `name` and never generates one (`400 name is required`). `PUT /api/v2/dashboards/{id}` **also requires `name`, and it must equal the record's current one** — a differing value is rejected with `400 name is immutable; cannot change from "x" to "y"`. So an update must send the _record's_ name, not the file's. Because `name` is a per-instance slug (`mysql-red-qdjvnvd7` on one instance, `mysql-red-licw80b8` on another), tooling must match dashboards by `spec.display.name` (the human title, stable everywhere) and keep `name` only for creating. Note the earlier version of this note claimed the HTTP endpoint does not enforce immutability and that the rule was the MCP server's — that was wrong; the MCP server enforces it too, and the endpoint genuinely rejects a change.

**The list is a summary.** `GET /api/v2/dashboards` nests items under `.data.dashboards`, each with only a summary `spec` (effectively just `display`) — so `.spec.panels` reads as 0 there. Read panels from `GET /api/v2/dashboards/{id}`, which returns the full object.

**Legacy dashboards cannot be updated.** A dashboard the v0.135 migration could not convert keeps `schemaVersion: "v5"` and `legacy: true`, and the V2 API refuses to touch it: **`501 … is not in v6 schema` on GET and on PUT alike**. It must be REPLACED — create the corrected V2 dashboard, then delete the legacy record — never patched in place. It still appears in the list, which is how you detect it. A malformed V1 field (e.g. `panelMap` as an array where an object is required) is the usual reason a dashboard lands there.

**Saved views.** `GET /api/v2/saved_views` returns a plain array under `.data` (not a nested key), the title is `spec.displayName`, and `PUT /api/v2/saved_views/{id}` answers **204 with a zero-byte body** — an empty body is success, not a failure.
