---
date: 2026-08-25
keywords: ["shell", "grep", "word-boundary"]
trigger-on: ["grep-word-boundary-portable"]
---

## GNU grep rejects `[[:<:]]`/`[[:>:]]`; use `\b` for portable word boundaries

GNU grep fails with "Invalid character class name" on the BSD-style word-boundary classes `[[:<:]]`/`[[:>:]]`, while `\b` works on both GNU and BSD (macOS) grep. When writing cross-platform grep patterns (dev-bot must run on Linux Mint, Fedora, and macOS), use `\b(error|fatal)\b`, not `[[:<:]]...`. Caveat: `\b` treats hyphens as word boundaries, so `error-handling.md` still matches `\berror\b` — acceptable for heuristic scans, but test plural forms ("0 errors") which correctly do not match.
