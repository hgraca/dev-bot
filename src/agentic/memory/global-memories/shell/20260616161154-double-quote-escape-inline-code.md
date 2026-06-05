---
date: 2026-06-16
keywords: ["shell", "bash", "quoting", "python", "heredoc"]
---

## Double-quote chars inside bash double-quoted string need escaping

When passing inline code via `python3 -c "..."` (or any `bash -c "..."`), double-quote characters (`"`) inside the string must be escaped as `\"` to prevent bash from interpreting them as closing the outer double-quoted string. Wrapping in single-quotes (`'"'`) does NOT work — bash still sees the `"` as a string terminator because the outer quoting is double-quotes. Fix: `'\"'` — bash treats `\"` as a literal `"` and passes it through to Python/PHP/whatever. Compare: `'\\\\'` on the other hand IS correct — bash processes `\\\\` → `\\`, and Python sees `'\\'` (single backslash literal), so that pattern needs no change.
