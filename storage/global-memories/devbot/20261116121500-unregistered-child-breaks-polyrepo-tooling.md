---
date: 2026-11-16
keywords: ["devbot", "polyrepo", "project-memory", "worktree", "project-for-path"]
aliases: ["unregistered child", "list-projects", "worktree create refuses polyrepo root"]
trigger-on: ["devbot-polyrepo-child-work", "devbot-worktree-create"]
---

## Not every folder in a polyrepo is a registered project

In a `workspace.type: "polyrepo"` session, resolution goes through the global config's `projects`
array. A repository that lives in the workspace but is **not registered** (in Get-e: `slack-bot`,
`raido-integration`) resolves to the polyrepo root, with three consequences that all look like bugs:

- `devbot tool project-for-path <unregistered>` returns the **root** project (`type: polyrepo`) —
  so its `workflow`/`commit_memory` are the root's, not a child's.
- `devbot tool project-memory <unregistered>` prints the **root** vault, not a child vault. There is
  no child memory to load, so this is correct behaviour, but it reads like a wrong result.
- `worktree.sh create`/`enabled` **refuse a polyrepo root** (`FATAL: … is a polyrepo project, not a
  codebase`), so the standard worktree-first flow is unavailable. Create it by hand instead:
  `git -C <repo> worktree add -b <branch> <devbot_dir>/worktrees/<repo>-<slug> origin/<default>`.

Confirm registration first with `devbot tool list-projects --compact` (or `--only <name>`) before
assuming a child's config, memory or worktree tooling applies.
