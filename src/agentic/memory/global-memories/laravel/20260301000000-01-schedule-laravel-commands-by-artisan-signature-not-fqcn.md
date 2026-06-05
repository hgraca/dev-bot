---
date: 2026-03-01
keywords: ["laravel", "artisan"]
---

## Schedule Laravel commands by artisan signature, not FQCN

When: registering a command in `$schedule->command(...)` whose source class lives under a namespace that may be reorganized.
Pattern: pass the artisan signature string instead of the class FQCN.

```php
// Avoid — couples Kernel.php to the command's namespace location:
$schedule->command(FindAndCreateMissingCustomerInvoicesCliCommand::class)->dailyAt('10:00');

// Prefer — survives namespace moves with no Kernel.php edit:
$schedule->command('find-and-create-missing-customer-invoices')->dailyAt('10:00');
$schedule->command('find-and-create-missing-supplier-statements', [
    '--create' => true, '--from' => '2026-03-01',
])->dailyAt('11:00');
```

Why: TP-6168 surfaced two pre-existing PHPStan errors in `Kernel.php` whose `use` imports pointed at stale namespaces after CLI commands were moved. The FQCN pattern silently rots whenever a command moves; the artisan-signature pattern doesn't, because Laravel resolves the signature through the command registrar at runtime. Trade-off: lose IDE jump-to-definition from Kernel.php — acceptable, since the signature is grep-able and the Kernel is read rarely.
