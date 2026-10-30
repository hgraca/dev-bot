---
date: 2026-10-30
keywords: ["php", "rector", "cacheClass", "dev-tools"]
aliases: ["Call to undefined method RectorConfig::cacheClass", "rect-dry-run fails"]
trigger-on: ["rector-config", "php-static-analysis"]
---

## Rector 2.6 removed `RectorConfig::cacheClass()`

Any config calling `$rectorConfig->cacheClass(FileCacheStorage::class)` dies at `make .rect-dry-run` with `Call to undefined method Rector\Config\RectorConfig::cacheClass()` on Rector 2.6+ — before any rule runs, so the error looks unrelated to the change under test. The call was always redundant: `Rector\Caching\CacheFactory` defaults `$cacheClass` to `FileCacheStorage` in 2.4 as well as 2.7. Delete the line rather than guarding it with `method_exists()` — phpstan analysing the older vendor reports `function.alreadyNarrowedType: will always evaluate to true`. `cacheDirectory()` still exists and is unchanged.
