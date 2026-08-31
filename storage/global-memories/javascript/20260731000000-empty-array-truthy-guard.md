---
date: 2026-07-31
keywords: ['javascript', 'react', 'truthy']
---

## Empty array is truthy — guard conditions must check length

`if (itbData?.excludedHotels)` evaluates to `true` when `excludedHotels` is an empty array `[]`. This causes `setExcludedHotels(new Set([]))` to run, clearing all exclusions. The fix: check `(itbData.excludedHotels as string[]).length > 0` before applying. Same applies to any array where empty means "no data" rather than "empty data".
