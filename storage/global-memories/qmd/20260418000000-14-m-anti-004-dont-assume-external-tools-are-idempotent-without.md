---
date: 2026-04-18
keywords: ["qmd"]
---

## M-ANTI-004: Don't assume external tools are idempotent without testing

qmd collection add failing on re-runs despite documentation claiming idempotency
Test idempotency claims by running commands multiple times. Add existence checks before operations that claim to be idempotent but actually aren't.
