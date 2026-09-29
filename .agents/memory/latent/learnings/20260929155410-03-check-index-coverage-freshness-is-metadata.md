---
date: 2026-09-29
keywords: ["codebase-memory", "check-index-coverage", "freshness", "metadata"]
---

# check_index_coverage freshness reports index metadata, not drift from the tree

`check_index_coverage`'s per-path `freshness` field describes the index's own
coverage bookkeeping, not whether the graph matches the working tree. A build
records `generation` / `recording_status` / `coverage_version` in the index
metadata; when that metadata is absent or mismatched for a path, `freshness` reads
`missing` (with `recommended_action: read_source_and_reindex`), and once a build
records it, `metadata_match`.

Consequence: `freshness: missing` does not mean the graph is stale against your
edits, and `metadata_match` does not mean it is current. A scout read `missing`
as real drift and lost time chasing a phantom. A path added after the last index
shows `not_tracked` under `metadata_match`. Judge staleness from the index
generation timestamp versus the tree (or just re-run `index_repository`), not from
this field.
