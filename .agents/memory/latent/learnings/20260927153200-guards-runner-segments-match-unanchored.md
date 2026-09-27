---
date: 2026-09-27
keywords: ["guards", "regex", "find", "qmd", "anchoring"]
---

# Guards match command-RUNNER segments unanchored, so a pattern in any argument blocks

`src/agentic/guards/tools/guards.ts` splits the command on shell separators and
tests each segment's first word. For an ordinary segment the rule regex is
anchored to the segment start; but when the segment's command is a
COMMAND_RUNNER (`bash`, `sh`, `eval`, `xargs`, `find`, `sudo`, `docker`, …) or
the segment contains `$( )`/backticks, the UNANCHORED regex is used — the danger
can hide in the arguments.

Consequence: a bare-token regex over-blocks. `\bqmd\b` blocked
`find . -name '*qmd*'` (a harmless read-only search) because `find` took the
substring path and `qmd` sat between two `*`s. Fix: `(?<![*\w])qmd(?![*\w])` —
a word `qmd` not adjacent to a glob star — which still blocks `qmd update` and
`bash -c "qmd update"` (audit-69 NOTE-7).

Rule of thumb: write guard regexes for the unanchored substring path too.
Anchoring only holds for non-runner segments, and `\b` is not a safe boundary
there — `*` is a non-word char, so `\b` happily matches between `*` and `q`.
