---
date: 2026-08-18
keywords: ["mysql", "spatial", "st_within", "bounding-box", "full-scan"]
trigger-on: ["spatial-st-within-full-scan", "polygon-lookup"]
---

## ST_WITHIN(point, polygon) may not use the spatial index — pre-filter by bounding box

SUPERSEDED by `20260818150000-spatial-bbox-columns-diverge-from-geometry.md` — the precomputed bbox columns can diverge from `polygon_area`, so this pre-filter wrongly excludes matching areas.

A spatial (R-tree) index on a `polygon` column is not reliably used by `ST_WITHIN(ST_GeomFromText('POINT(...)'), polygon_area)` in MariaDB/MySQL, so the query full-scans the table. Pre-filter with precomputed axis-aligned bounding-box columns before the exact geometry test: `WHERE lat_min < ? AND lat_max > ? AND lng_min < ? AND lng_max > ? AND st_within(..., polygon_area)`. The bbox predicate is a superset (a point inside a polygon is always inside its bbox), so correctness is preserved while the indexed bbox columns (maintained on save) narrow the candidates to a handful of polygons before the expensive exact test runs.
