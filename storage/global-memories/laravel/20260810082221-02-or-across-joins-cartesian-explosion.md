---
date: 2026-08-10
keywords: ["laravel", "eloquent", "query-performance", "union", "orWhere"]
trigger-on: ["eloquent-orwhere-multiple-joins", "or-across-joins-performance"]
---

## OR condition across multiple independent LEFT JOIN paths causes cartesian product explosion

When using `orWhere` to filter across two or more independent join paths (e.g., `->leftJoin('table_a', ...)->leftJoin('table_b', ...)->where('a.col', X)->orWhere('b.col', X)`), MySQL must join all tables before evaluating the OR. Each row in the driving table multiplies by the rows in each joined path, creating N×M rows.

Fix: split into separate query builders, each only joining tables on a single path, then unite with `->union()`. UNION DISTINCT handles deduplication. Example from `get-e/core` billing handler:

```php
// BROKEN: 5-table cartesian explosion
$q->leftJoin('path_a', ...)->leftJoin('path_b', ...)->where('a.col', X)->orWhere('b.col', X);

// FIXED: two focused queries united
$a = BillingTrip::query()->select('col')->leftJoin('path_a', ...)->where('a.col', X);
$b = BillingTrip::query()->select('col')->leftJoin('path_b', ...)->where('b.col', X);
return $a->union($b);
```
