---
date: 2026-08-20
keywords: ["php", "closure", "by-reference", "array", "return-by-value"]
trigger-on: ["closure-reference-array-return"]
---

## Array returned from a helper is a copy — closures writing via &$var don't propagate through the return

PHP arrays are value types: a helper that captures a local array by reference in closures (`use (&$recording, $span)`) and then returns `['recording' => $recording]` hands the caller a COPY of the array at return time. The closures keep appending to the helper's local variable, so the caller's copy stays empty. Symptom: a test double that records calls into a returned array appears to record nothing — assertions on `$fixture['recording']['events']` show size 0 even though the double was invoked. Fix: pass the array into the helper by reference (`private function attachRecordingSpan(array &$recording): ScopeInterface`), or store it as a class property shared with the closures, so closures and caller mutate the same variable.
