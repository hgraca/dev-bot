---
date: 2026-08-19
keywords: ["phpunit", "ordering", "sort", "tie-break", "test-design"]
trigger-on: ["multi-key-ordering-test", "orderby-secondary-sort", "sort-tie-break-test"]
---

## A test asserting a multi-key sort must tie fixtures on the primary key

When a test verifies a multi-key ordering (e.g. `orderBy('start')->orderBy('end')`), fixtures that each have a unique first-key value only prove the primary sort — a broken or missing secondary `orderBy` still passes. The test must include at least two fixtures that share the same primary-key value but differ on the secondary key, and assert their relative order. Example: a test named `it_orders_rules_by_start_then_end` had three rules with distinct `start` values, so removing `orderBy('end')` would not fail it; the fix reuses one `start` value for two rules with different `end`s and asserts the tie-break order. This is a distinct failure mode from "name claims ordering but body only asserts existence" — the test asserts ordering yet still leaves the secondary key untested.
