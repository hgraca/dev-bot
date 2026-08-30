---
date: 2026-08-13
keywords: ["devbot", "small-fix", "perfectionism", "surgical-changes", "profile"]
---

## DevBot fixes small in-scope defects directly instead of flagging them

DevBot's profile now separates trivial defects from decisions: a small, clearly-correct, low-risk defect spotted in code already being touched (typo, stray whitespace in a string, wrong fallback, missing null-check) is fixed directly as part of the task and noted in the summary — not flagged for approval. Anything behavioral, architectural, or outside the change's blast radius is still surfaced first.

Rationale: the human repeatedly observed DevBot asking "want me to fix this too?" for tiny, obvious defects (e.g. a leading-space alt text), adding friction to every task. The ask-first principle is preserved for decisions; trivia is fixed inline. Trivial unrelated fixes go in the same commit with a one-line summary note — no separate atomic commit required.

Encoded in `src/agentic/devbot/agents/devbot.md` ("Small-Fix Perfectionism" section) and `.agents/memory/active/karpathy-instructions-annex.md` (an annex amending the external, uneditable karpathy "Surgical Changes" rule).
