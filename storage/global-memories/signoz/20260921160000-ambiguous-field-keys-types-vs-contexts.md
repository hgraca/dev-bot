---
date: 2026-09-21
keywords: ["signoz", "field-context", "data-types", "ambiguity", "logs"]
trigger-on: ["signoz-field-filter", "otel-attribute-collision"]
---

## Ambiguous field keys: type ambiguity only slows queries, context ambiguity returns nothing

SigNoz's field catalog is data-driven, so the same key name appearing with two data types or in two contexts produces `Key X is ambiguous`. Type ambiguity (e.g. `status` present as both attribute/string and attribute/number) is comparatively benign: SigNoz searches across all types, so queries still return data — just slower, and type comparisons can misbehave; force a single type with the `field:type` syntax (`status:float64 >= 500`). Context ambiguity (e.g. `body` present as both attribute and log) is worse, because a bare `body = ...` can silently return nothing — pin the context explicitly (`log.body`, `attribute.body`, `resource.service.name`). Because the catalog is derived from the rows present, fixing the collector does not clear the warning immediately: the old rows keep both variants alive until they age out of retention (3 days in this project), so "fixed collector" and "clean catalog" are different milestones. Reference: signoz.io/docs/userguide/field-context-data-types/.
