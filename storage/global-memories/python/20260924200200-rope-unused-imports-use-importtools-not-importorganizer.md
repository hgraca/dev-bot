---
date: 2026-09-24
keywords: ["python", "rope", "importutils", "unused-imports", "refactoring"]
trigger-on: ["rope-refactoring", "rope-unused-imports"]
---

## rope: use `ImportTools.organize_imports`, not `ImportOrganizer`, to remove unused imports

`rope.refactor.importutils` exposes two similar-looking entry points. `ImportOrganizer.organize_imports(resource, offset=None)` performs the *whole* tidy-up — with `ImportTools` defaults `unused=True, duplicates=True, selfs=True, sort=True` — and returns a ready `ChangeSet` (or `None` when nothing changed), so it also sorts and rewrites self-imports. For a focused "remove unused imports" pass, call the lower-level `ImportTools(project).organize_imports(pymodule, unused=True, duplicates=False, selfs=False, sort=False)`, which **returns the new source text** (not a change set); wrap it yourself (`ChangeSet(...).add_change(ChangeContents(resource, new_source))`) and skip the change when the text is unchanged.
