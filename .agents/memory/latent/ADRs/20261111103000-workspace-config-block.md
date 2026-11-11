---
date: 2026-11-11
keywords: ["devbot", "workspace", "config", "polyrepo", "migration"]
aliases: ["workspace block", "monorepo rename", "supervisor rename"]
see: ["ADRs/20261023213258-canonical-workflow-resolver.md"]
supersedes: ["ADRs/20261023213258-canonical-workflow-resolver.md"]
---

## Workspace behaviour lives in one `workspace` block

A dev-bot config now carries `workspace: { type: "repo" | "polyrepo", commit_memory: bool, workflow: "worktrees" | "trunk" }` instead of the flat `commit_memory` / `workflow` / boolean `monorepo` (formerly `supervisor`) keys. The global config documents the defaults; a project config states only the keys it overrides, resolved project-first then global then built-in default by `_devbot_get_workspace_config` (a `read_jsonc.py <file> workspace <key>` lookup) and `_devbot_get_workflow`. `type: "polyrepo"` replaces the boolean as the name for the container project. The cut is hard — no reader falls back to a flat key — so `src/_shared/migrate_workspace_config.py` rewrites an existing config in place: a tokenizer walks string/comment/object-depth state, rewrites one top-level key at a time, keeps every other byte, verifies by parsing and swaps atomically through a symlink. It runs in `devbot update` **before** the global reconciler (which deletes runtime keys the dist no longer carries) and in `devbot init` per project; a missing tool or an unconvertible file returns non-zero so the reconciler is skipped rather than overwriting intent. `monorepo: false` migrates to an explicit `type: "repo"` rather than being dropped, so a project keeps its repo choice under a polyrepo global default. Known gap: a config from ≤1.14 that still carries the older `supervisor` key is not migrated by this tool — that rename was handled only by the intermediate release's `init`, so an upgrade that skips that release loses the flag.
