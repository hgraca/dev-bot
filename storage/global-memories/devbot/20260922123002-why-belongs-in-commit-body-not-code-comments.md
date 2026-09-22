---
date: 2026-09-22
keywords: ["devbot", "conventional-commits", "code-comments", "commit-body"]
trigger-on: ["code-comment-or-commit-body"]
---

## The why belongs in the commit body, not in code comments

Stakeholder rule (2026-09-22): a comment that explains why a line exists, what workaround it encodes, or what would break without it is a commit-description line that ended up in the wrong file — invisible to `git log`, rots in place, and duplicates a message the body could carry once. The reasoning goes into the Conventional Commits body; the code keeps only the 1–2 lines of non-obvious mechanics a reader cannot infer. The rule is encoded in every place an agent looks: `git-conventional-commits` states it under `## Body` where the body is defined, `git-atomic-commits` carries a pointer without restating it, `software-development`'s Comments rules gain the reciprocal half (minimal comments was already required, but nothing said where the reasoning belongs instead), and `devbot.md` folds it into the per-task commit protocol. The practical skill is spotting the inversion: a bare one-line subject over a five-line explanatory block, or a detailed body over a comment that repeats it.
