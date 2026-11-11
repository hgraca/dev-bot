---
date: 2026-11-11
keywords: ["prettier", "make-lint", "format-md", "dev-bot"]
---

# make lint's prettier standard is not the repo's prettier config

`make lint` checks markdown with explicit flags — `--parser markdown --print-width 999 --embedded-language-formatting off --ignore-path /dev/null` — while a bare `prettier --write <file>` resolves the repo's `.prettierrc.json`. A file formatted by the latter can still fail `make lint`; format with the lint's exact flags.

The failure is also hard to see: the `[warn]` line is appended to prettier's single progress line, which exceeds the 2 000-char tool-output truncation, so the whole md step can fail with no visible reason. Use `prettier ... --list-different "${md[@]}"` with the same flags to name the offending file.
