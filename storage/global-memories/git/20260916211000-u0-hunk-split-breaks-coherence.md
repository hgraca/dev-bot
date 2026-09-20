---
date: 2026-09-16
keywords: ["git", "apply", "hunk", "staging", "unidiff-zero"]
trigger-on: ["git-hunk-splitting", "git-apply-cached"]
---

## Splitting a diff with `-U0` breaks per-commit coherence: a logical edit's removals and additions land in separate hunks

When a change touches one file for several unrelated reasons and you want one commit per reason, splitting `git diff` into hunks and applying the matching subset with `git apply --cached` is a workable substitute for interactive `git add -p`. But generate that diff with **normal context (`-U3`), not `-U0`**. Zero context produces minimal hunks, which *sounds* ideal for fine-grained staging, and it is fine for whole-block insertions — but a single logical **edit** yields a removal hunk and an addition hunk that are separate, so staging only the additions leaves the old lines in place and the index becomes **scrambled** (observed: a replaced function body sitting next to its replacement). The give-away is that after staging "all" of a file, `git diff --stat` still lists it — the staged content is not the working file. With context, adjacency keeps each edit's `+`/`-` in one hunk and staging it yields a coherent tree. Verify with `git diff --stat -- <file>` being empty, and remember a fixup commit is only coherent *when squashed with its target*, so the right correctness check is the squashed tree.
