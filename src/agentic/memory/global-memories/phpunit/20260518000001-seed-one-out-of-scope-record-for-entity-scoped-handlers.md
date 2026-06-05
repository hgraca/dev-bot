---
date: 2026-05-18
keywords: ["phpunit", "integration-test", "isolation", "noise-data", "customer-filter"]
---

## Always seed one minimal out-of-scope record when testing entity-scoped handlers

When an integration test exercises a handler that filters by a specific entity ID (e.g. `customerId`, `supplierId`), include at least one in-period record belonging to a _different_ entity using the same supplier/resource. Without it, a missing filter in the handler would still pass because there is no competing data to leak through. The noise record costs one `createTrip()` call — far cheaper than the full population the original helper created. Pattern: create the minimal subject data, then add one out-of-scope record that _would_ appear if the filter were absent.
