---
date: 2026-11-02
keywords: ["devbot", "project-dist", "worktree", "config-rollout"]
aliases: ["project config template", "dist jsonc", "kubectl selection"]
---

## Project config lives in .devbot.project.dist.jsonc; read the main checkout's copy

A project's devbot settings have two files: the runtime `.devbot.project.jsonc` (machine-local, listed in `.git/info/exclude`, seeded from the dist at init) and the committed template `.devbot.project.dist.jsonc`. Only the dist is shareable, so a settings change that must survive `devbot reinit` or reach teammates has to land in the dist. The task's shorthand `.devbot.proj.jsonc` / `.devbot.proj.dist.json` names neither file — resolve it to the real pair before writing anything.

When rolling a config change across sibling repos inside worktrees, build the dist from the **main checkout's** existing dist, not the worktree's: `worktree.sh create` cuts the branch from `origin/<default>`, so a dist that exists only locally (staged but uncommitted) is invisible there, and a "copy the runtime over it" step silently replaces curated entries (modules, commit_memory) with a runtime snapshot. Detect it with `git -C <repo> status --porcelain -- .devbot.project.dist.jsonc` before generating.

Selections (`aws_connections`, `datasources`, `kubectl`) name entries from the **global** catalogues; they are opt-ins, not definitions — an unknown name is a WARN at init, not an error. Per-project `kubectl` arrays only work from dev-bot PR #40 onward, which made the global `kubectl` node a catalogue.
