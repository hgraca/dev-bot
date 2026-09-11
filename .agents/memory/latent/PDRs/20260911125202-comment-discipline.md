---
date: 2026-09-11
keywords: ["comments", "docblocks", "code style", "software-development"]
---

## Comment discipline: no prose inline; docblocks only when they earn their place

Comments are a last resort, not narration. No prose comments in the middle of code — they restate what the code says and rot as it moves; names and structure carry the meaning. Docblocks are written only when the function/method signature is not self-documenting (non-obvious contract, side effects, ordering, units, a surprising return) or a static-analysis tool requires one; a docblock that merely restates the name and parameters is noise. Genuinely unreadable code (a little-known native function, a dense call chain) gets at most 1–2 lines — but the preferred fix is to extract it into a function with a short, meaningful name (≤ ~32 chars), which states the intent and is testable. Encoded in the `devbot:software-development` skill's `### Comments` section; the PHP annex deliberately does not duplicate the rule.
