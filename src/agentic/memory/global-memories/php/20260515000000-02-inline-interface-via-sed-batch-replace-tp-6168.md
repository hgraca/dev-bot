---
date: 2026-05-15
keywords: ["php"]
---

## Inline interface via sed batch replace (TP-6168)

Context: `NetsuiteClientInterface` inlined into concrete `NetsuiteClient` across 11 service files + test + provider.
Pattern: single `sed -i` loop over file list — two passes per file: (1) replace full `use` import line, (2) replace bare type-hint token. Then update provider binding, remove `implements`, delete interface file.
Verify: `grep -rn "InterfaceName" app/ tests/ --include="*.php"` must return zero.
ServiceProvider: `singleton(Concrete::class)` (no second arg) when no interface binding needed.
