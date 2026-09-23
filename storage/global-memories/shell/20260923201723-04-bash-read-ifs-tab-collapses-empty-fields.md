---
date: 2026-09-23
keywords: ["shell", "bash", "read", "ifs"]
trigger-on: ["bash-read-ifs-empty-field"]
---

## `read` with `IFS=$'\t'` silently drops empty fields

Bash treats tab as **IFS whitespace**, so `IFS=$'\t' read -r a b c d` collapses runs of tabs and strips leading/trailing ones — an empty field in the middle is lost and every later field shifts one position left. This silently mis-parsed a `op\t\tfrom\tto` record into `a=from, b=to, c=''`, turning valid input into "required argument missing" with no hint that parsing was the problem. When a delimiter-separated record may contain empty fields, use a **non-whitespace** separator — `IFS=$'\x1f'` (ASCII unit separator) preserves them — or avoid the encoding entirely and let a JSON-aware tool unpack the record.
