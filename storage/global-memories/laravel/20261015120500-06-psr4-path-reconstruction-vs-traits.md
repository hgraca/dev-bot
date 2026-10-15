---
date: 2026-10-15
keywords: ["laravel", "php", "psr-4", "stack-trace", "traits"]
aliases: ["reconstruct file path from namespace", "class name to file name"]
trigger-on: ["php-stacktrace-path", "psr4-path-derivation"]
---

## Deriving a file path from a class name is unsafe for trait and inherited methods

Mapping a stack frame's class back to its file through PSR-4 (`App\` → `app/`, so `App\Jobs\Allocation\AllocateToSupplierJob` → `app/Jobs/Allocation/AllocateToSupplierJob.php`) does work for a class's own methods and can be verified against the checkout — but it is **wrong whenever the frame belongs to a trait or a parent class**, because the frame's file is where the method is _defined_, not where the class lives. In a Laravel codebase that case is common: the frame `App.Events.BookingWasCreated.restoreModel(SerializesAndRestoresModelIdentifiers.php:112)` maps to `app/Events/BookingWasCreated.php`, yet `restoreModel` is defined in `vendor/laravel/framework/src/Illuminate/Queue/SerializesAndRestoresModelIdentifiers.php` and the class file does not contain it at all — so the synthesised path reads authoritative while pointing at unrelated code, which is worse than the terse basename the trace actually provides. When a source location must be shown, render the frame as recorded (class.method plus the basename and line already carried) rather than reconstructing a path, and verify any reconstruction against the real checkout before trusting it.
