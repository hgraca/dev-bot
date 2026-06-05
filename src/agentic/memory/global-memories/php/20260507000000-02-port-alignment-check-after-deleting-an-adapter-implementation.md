---
date: 2026-05-07
keywords: ["php", "netsuite"]
---

## Port-alignment check after deleting an adapter implementation

When: deleting an adapter class (e.g. infra service) that implemented a method on a Port interface.
Pattern: after deleting the adapter, audit the Port interface for orphaned methods. If the deleted adapter was the only implementation and the method is no longer called from any consumer, remove the method from the interface and from the other adapters that implemented it.

Concretely during TP-6168 commit `432b4d0e7`:

- Deleted `UpsertSalesOrderService` (the only place that implemented `upsertSalesOrder` and `isSalesOrderClosedForInvoicePeriod` business logic for the V1 path).
- Result: `Netsuite.php` (the `Erp` port adapter) had two methods that delegated only to the deleted service.
- Action: removed both methods from `Netsuite.php` AND from the `Erp` interface itself.

Skip the step → leave dead methods in interface → next refactor has to revisit the same interface → erosion. The check costs ~1 minute (`grep` the interface methods across the codebase) and prevents this.
