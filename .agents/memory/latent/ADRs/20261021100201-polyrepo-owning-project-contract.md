---
date: 2026-10-21
keywords: ["polyrepo", "owning-project", "worktree", "devbot"]
aliases: ["cross-project scoping", "project-for-path", "polyrepo sessions"]
see: ["PDRs/20261009084425-polyrepo-project-memory-scoping.md", "ADRs/20261009084426-polyrepo-memory-scope-resolution.md"]
---

## Every project-scoped module resolves the owning project in a polyrepo session

A `workspace.type: "polyrepo"` project is a container for the sibling repositories registered in the global `projects` array; it is often a git repository with no commits and no remote. Memory already scoped itself by touched path, but every other module assumed the session's cwd was the project, so worktree creation, commits, PRs, `make`, datasources and indexes could target the container.

The contract — documented in `docs/polyrepo-sessions.md` and linked from each affected module — is: resolve the owning project from the files in play, read that project's config project-first, run repo-scoped commands there, and treat only coordination work as the polyrepo's. It is implemented by one resolver, `devbot tool project-for-path <path>`, which reuses `src/_shared/resolve_project.py` (longest registered prefix) and resolves scalars project-first; `modules` merges per key and `datasources` is the project's own selection (the global key is a catalogue, not a selection). `worktree.sh create` and `enabled` gained `--project` and refuse a polyrepo root outright — inferring from "no commits" is not enough, because a polyrepo that gains a coordination commit would silently become the worktree target. In a normal project the contract is inert.
