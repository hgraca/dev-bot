---
date: 2026-10-09
keywords: ["devbot", "supervisor", "resolve-project", "search-memories"]
see: ["PDRs/20261009084425-supervisor-project-memory-scoping.md"]
---

## Supervisor memory scope resolution

Implementing the supervisor model (PDR `PDRs/20261009084425-supervisor-project-memory-scoping.md`): a path→project resolver (`src/_shared/resolve_project.py`) matches the **longest** registered `.devbot.global.jsonc::projects` path that is a path-component prefix (realpath-based, so `/a/b` never matches `/a/bc`; a missing config fails open to a caller-supplied default), exposed to bash as `_devbot_resolve_project_for_path` and mirrored in `search-memories.py` (`resolve_supervisor`, `resolve_registered_project`, `supervisor_read_projects`). `search-memories` gains `--focus <path>` (repeatable); a supervisor session searches the touched projects + itself + the global store — mdctx ranks hits **project-by-project in read-set order, then global** (never comparing corpus-relative BM25 across vaults), and qmd searches each read-set collection via `search_qmd_scoped` (warning on collection-name collisions; falling back to the global collection when no project collection resolves). The `file.edited` reindex hook passes `--path {file}` so a child's note reindexes the child's own index; `reindex-passive-memories.sh` keeps the session worktree when the resolved project IS the worktree or an ancestor of it, so a linked worktree at `<project>/<devbot_dir>/worktrees/<slug>` is reindexed in place, never the main checkout. `commit_memory`/`worktrees` are resolved for the owning project, never the supervisor.
