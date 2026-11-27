---
date: 2026-11-27
keywords: ["shellcheck", "SC1073", "directive", "comment"]
---

## A comment that starts with `# shellcheck` is parsed as a directive, even when it is prose

Writing `# shellcheck directive (this repo's lint…)` as an explanatory comment makes shellcheck read
`directive` as a directive key and abort with SC1073 / SC1072 ("Couldn't parse this shellcheck
directive"), failing a lint run over a file whose code is fine. Any comment beginning with the literal
`# shellcheck` at the start of the line is a directive; prose must not start that way.

Two safe habits: put the directive only in its real form (`# shellcheck shell=bash`,
`# shellcheck disable=SC…`) and word prose as "the lint directive…" (no `# shellcheck` prefix), or keep
the word in the middle of the line. The same applies to a file that is _rendered_ into another file:
strip directive lines (`sed '/^# shellcheck /d'`) so they do not land in a user's rc.
