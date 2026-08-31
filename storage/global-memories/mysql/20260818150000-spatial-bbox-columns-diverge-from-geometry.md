---
date: 2026-08-18
keywords: ["mysql", "spatial", "st_within", "bounding-box", "geometry"]
trigger-on: ["spatial-st-within-full-scan", "polygon-lookup"]
---

## Bounding-box pre-filter columns can diverge from the polygon geometry — don't trust them

SUPERSEDED by `learnings/20260818151000-areafactory-geojson-curly-quotes-break-bbox.md` — production verification showed the bbox columns are reliably in sync (0/32,062 divergent); the divergence was a test-fixture issue only.

Pre-filtering `ST_WITHIN(point, polygon_area)` with manually-maintained `lat_min/lat_max/lng_min/lng_max` columns is unreliable: those columns are recomputed from a SEPARATE `geo_json` column on save (a model `saving` observer), not derived from `polygon_area` itself. When `geo_json` is empty/invalid or `polygon_area` is set independently (e.g. directly via `ST_GeomFromText` in a factory/seed), the bbox columns no longer bound the polygon, so the assumed-superset filter wrongly excludes matching areas. This broke `FindAreaService::find()` — areas silently disappeared from pricing. Safer alternatives: derive the MBR from the geometry itself (`MBRContains(polygon_area, point)` as the sargable pre-filter, then the exact `ST_Within`), or skip the bbox pre-filter and rely on the exact spatial predicate. SUPERSEDES 20260818114500-st-within-needs-bounding-box-pre-filter.md.
