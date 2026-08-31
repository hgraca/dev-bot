---
date: 2026-08-22
keywords: ["shell", "awk", "in_block", "jsonc", "array"]
trigger-on: ["awk-array-insert"]
---

## awk in_block flag breaks when array brackets share one line

An awk state machine that inserts into an array — matching `/"plugin": \[/` to set `in_block=1` and `in_block && /\]/` to clear it — only works when the array spans multiple lines. If the array is written on one line (`"plugin": []` or `"plugin": ["a","b"]`), the `[` match sets the flag but the same-line `]` is never tested against the `in_block && /\]/` rule, so every following line is buffered as "array body" until some unrelated `]` appears, and the inserted entry lands in the wrong array (corrupting the file). Fix: add a dedicated same-line rule `/"plugin": \[[^]]*\]/` that matches the whole single-line array and rewrites it inline (empty → `["entry"]`, non-empty → append before `]`) BEFORE the generic multi-line rules run. In awk, `[^]]*` cannot span newlines, so it naturally scopes to one line.
