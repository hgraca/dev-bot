---
date: 2026-10-30
keywords: ["devbot", "reconcile", "MERGE_MAPS", "offset", "global-config"]
trigger-on: ["reconcile-merge-maps"]
---

# reconcile_global_config: Re-scan Offsets After Each Nested Map Merge

Adding a second map to `MERGE_MAPS` in `src/_shared/reconcile_global_config.py` exposed a stale-offset bug: the loop cached `new_by_key` once, but merging one map shifts every property below it, so the next map was read at its old `value_start` and reconciliation failed with `ERROR: cannot reconcile global config: expected ':' after key ...`. Recompute `_top_level_props(new_text)` inside the loop (or merge in reverse document order) and regression-test a config where `external_modules` precedes `modules` and both maps lack dist entries. Keep `modules` additive in `MERGE_MAPS` so a newly shipped module default reaches existing installs while an explicit machine value wins.
