---
date: 2026-05-15
keywords: ["graphify", "path-arg", "output-dir", "graphifyignore", "scoping"]
superseded_by: ["graphify/20261002180415-01-graphifyignore-negation-must-be-bare.md"]
---

## `graphify update <path>` controls output dir, not just scope

> **Superseded in part by** `graphify/20261002180415-01-graphifyignore-negation-must-be-bare.md` (2026-10-02) — the `!/src` example below re-includes nothing on graphify 0.8.35; use the bare `!src` form.

`graphify update <path>` writes `graphify-out/` **relative to `<path>`**, not relative to CWD.
So `graphify update src` creates `src/graphify-out/` — breaking the project-root symlink to central storage.

**Fix**: always pass `.` and restrict what gets indexed via `.graphifyignore` exclusion rules:

```
/*
!/src
/src/graphify-out
```

This keeps `graphify-out/` at the project root while scoping indexing to `src/` only.

See [[20260417000000-02-m-arch-007-per-project-storage-isolation-prevents-data-corruption.md]] for storage layout context.
