---
date: 2026-07-02
keywords: ["laravel", "eloquent", "performance", "whereExists"]
trigger-on: ["eloquent-left-join-distinct", "eloquent-search-filtering"]
---

## Use EXISTS subqueries instead of LEFT JOINs for filtering by related table data

When an Eloquent query needs to filter by a one-to-many relationship (e.g., find bookings whose custom fields contain a value), using `leftJoin` on the related table followed by `select distinct` on the main table creates a performance problem: each row of the main table gets multiplied by the number of related rows, and DISTINCT must deduplicate a large temp table. Instead, use `->whereExists(function ($sub) { $sub->select(DB::raw(1))->from('related_table')->whereColumn(...)->where(...) })`. This avoids row multiplication entirely and eliminates the need for DISTINCT. The same pattern applies to `orWhereExists` for alternative conditions. For Laravel's Query Builder, use `DB::table(...)->whereExists(...)`; for Eloquent, `->whereExists(...)` works on the Builder.
