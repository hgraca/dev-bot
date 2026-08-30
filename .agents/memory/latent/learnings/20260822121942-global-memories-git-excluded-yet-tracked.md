---
date: 2026-08-22
keywords: ["devbot", "memory", "gitignore", "global-memories"]
---

# global-memories/ is git-excluded yet 484 files remain tracked

`src/agentic/memory/global-memories/` is listed in `.git/info/exclude` (line 37), so NEW global memory notes written there cannot be `git add`ed — the operation fails with "ignored". But 484 files under it were committed before that rule and remain tracked, so `git status` still shows modifications to old notes as `M`. Net effect: cross-project gotchas/learnings written to `global-memories/<tech>/` are never persisted to git, while older ones still are — a silent, half-frozen state. When writing a global memory note, expect `git add` to refuse it; commit tracked-file edits with `git add -f`, and treat the exclude-vs-tracked inconsistency as a decision to resolve (either remove the exclude rule or truly untrack the 484 files).
