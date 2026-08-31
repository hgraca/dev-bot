---
date: 2026-08-14
keywords: ["php", "array-key", "numeric-string", "strict-comparison"]
trigger-on: ["php-array-numeric-string-key"]
---

## Numeric-string array keys are coerced to integers

Assigning `$arr["56261"] = $v` stores the key as `int 56261`, not a string — PHP casts numeric-string keys to ints. It bites when you later `foreach ($arr as $id => ...)` and compare `$id` against a string with a strict check (`===`, `assertContains`, `in_array(..., true)`): `56261 !== "56261"`. Common in tests: building a map keyed by record IDs, then asserting against `array_column($rows, 'id')` (which returns strings). Fix: cast the key back before the strict comparison — `$id = (string) $id;` — or use loose comparison deliberately.
