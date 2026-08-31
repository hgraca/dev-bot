---
date: 2026-05-06
keywords: ["php", "rename", "sed", "awk"]
---

## Class-rename via sed/awk creates duplicate `use` statements

A mechanical rename of class B → A (e.g. `InternalSalesOrderId` → `ErpSalesOrderId`) leaves duplicate `use App\...\A;` lines in every file that already imported A AND imported B. PHP fatal: `Cannot use ... as ErpSalesOrderId because the name is already in use`. Hit during the `InternalSalesOrderId` rename — 7 files broke (`Netsuite.php`, `BillingErpPersistenceService.php`, `Erp.php`, `NetsuiteClient[Interface].php`, `BillingSalesOrder.php`, one test). Rector and unit tests both blew up before the rename finished propagating.
Fix: After any class-rename refactor, run `grep -rn "use FQCN;" app/ tests/ | awk -F: '{print $1}' | sort | uniq -c | awk '$1 > 1'` to find duplicates, then dedupe with `awk '!/^use FQCN;$/ || !seen++' file > file.tmp && mv file.tmp file`. Better: include the dedupe step in the rename plan from the start, OR use Rector's `RenameClassRector` which handles import dedup automatically.
