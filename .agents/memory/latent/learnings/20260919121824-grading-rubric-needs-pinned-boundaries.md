---
date: 2026-09-19
keywords: ["grade-tools", "rubric", "tools-grades", "evaluation", "agent-instructions"]
---

# A grading rubric with unpinned boundaries produces a value, not signal

The `grade-tools` skill produced a session row of eleven tools with ten `4`s — a row that cannot drive keep / remove / substitute, which is the matrix's only purpose. The cause was the rubric rather than the grader: two adjacent boundaries were undefined, so the lazy call was always the middle one. "Used, helpful, but a substitute existed" (3) invites "almost anything can be replaced"; pin it — a replacement counts only if you would actually have reached for it, in that session, with no extra setup. "Critical" (5) invites the flattering read; pin it — 5 means the absence would have made the outcome materially _wrong_ (a commit sweeping in a colleague's uncommitted work, a behaviour change shipped on manual evidence), not merely less tidy. Undefined boundaries cluster ratings at one value, and a cluster is indistinguishable from a real assessment — which is what makes it dangerous rather than merely useless. Two further rules keep the signal: a flat row (five or more tools graded, none below 4) means re-read before writing, because an unexamined row is likelier than an excellent one; and the notes must close with the tools NOT reached for, since a grade exists only for tools that were used and the unused alternative is the strongest improvement signal available.

## Related tooling lesson

An append-only recorder with no update or delete forces corrections into a hand-edit of its data file — which the same skill forbids — so a recorder that will occasionally be mis-used needs `--update` / `--delete` in its interface, not a rule against touching the file. The worked example in the skill was also unrunnable: it passed `--skill devbot:makefile=3` while its notes never named `makefile`, and the script rejects a 1-3 that does not name its tool. Examples that are never executed rot silently; a doctest-style check, or simply running the example once against a sandbox root, catches it.

## Routing note

This note belongs in the shared `global/devbot/` store (the skill ships to every consumer project), but `.git/info/exclude` line 9 — `storage/global-memories/**`, a stray machine-local rule outside the devbot-managed block — makes new files there untrackable, while the 113 existing notes stay tracked because git tracks them regardless. It is filed here instead until that rule is resolved.
