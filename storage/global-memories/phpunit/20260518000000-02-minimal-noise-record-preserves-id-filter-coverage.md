---
date: 2026-05-18
keywords: ["phpunit", "integration-test", "isolation", "factory", "performance"]
---

## Add one minimal out-of-scope record when reducing integration test data

When optimising an integration test by removing bulk seed data, check whether any of that data served as isolation proof — i.e. it would have caught a missing filter (wrong customer, wrong supplier, wrong period). If so, removing it all silently weakens the test: a handler bug that ignores the scoping parameter would still pass because no competing data exists. The fix is cheap: add exactly one record that is in-scope for the dimension being filtered out (same billing period, same supplier) but belongs to a different entity (different customer ID). One extra `createTrip()` call (~0.5s) restores the coverage that dozens of full-factory records previously provided. Applied in `CreateSalesOrdersPerBillingPeriodHandlerTest` and `CreateSalesOrdersPerSupplierPerBillingPeriodHandlerTest` after reducing from 96 trips to 12 trips per test.
