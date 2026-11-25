---
title: "Memory"
description: "The knowledge vault — recall, session capture, vault structure, pruning, and scratch notes."
commands: ["audit-memory", "prune-memories", "remember-session"]
skills: ["commit-memories", "create-todo", "memory-management", "prune-memories", "reconcile-work", "remember-session", "search-memory", "thinking"]
hooks: ["reindex-memories"]
tools: ["generate-mcp-guide", "reindex-memories", "reindex-passive-memories", "search-memories"]
---

The knowledge vault: what agents learned in earlier sessions, kept where the next session can find it.

## What it does

- **Recall** — `search-memory` looks up past decisions, learnings and gotchas before a problem is solved again.
- **Capture** — `remember-session` promotes what a session learned into the vault and routes each entry by kind; `commit-memories` publishes the captured notes as a standing pull request in the project that owns them.
- **Structure** — `memory-management` defines the vault layout and routing rules; `create-todo` captures an ad-hoc TODO as a work item under `work/todo/`; `prune-memories` (skill and command) keeps it from going stale; `reconcile-work` aligns the work-folder states (`todo` → `active` → `archive`), takes down landed worktrees and their local branches, and deletes the session's `thinking/` scratch files at wrap-up; `thinking` provides those scratch files for work in progress.
- **Staying current** — a `file.edited` hook reindexes the vault as it changes, so a search never misses a note written moments ago.

## Session capture

The `remember-session` skill captures what was learned during a session and routes it to the knowledge vault — so the next session starts smarter.

- **Finish flow**: the primary agent runs `remember-session` once when the work is confirmed finished, before `[FINISHED]`; the captured notes are then committed and published through `commit-memories`
- **Publishing**: `commit-memories` groups the notes by the repository and stream that own them — the project's vault in the project's repository under `chore(agents): commit memories and lessons learned`, global lessons in the dev-bot store under `chore(global-memories): commit global memories and lessons learned` — and opens or appends each standing pull request without asking
- **Learning routing**: findings are categorized —
  - Product decisions → `memory/latent/PDRs/`
  - Architecture decisions → `memory/latent/ADRs/`
  - Gotchas → `memory/latent/global/<tech>/` or `memory/latent/learnings/`
- **Watermark tracking**: only new learnings since the last capture are processed

Say "wrap up", "remember session", or "capture session" to trigger it manually.

## Polyrepo sessions

A project with `workspace.type: "polyrepo"` runs sessions across the managed projects
registered in `.devbot.global.jsonc::projects`. Memory is scoped by the files
the session touches: `search-memories --focus <path>` searches the touched
projects' vaults + the polyrepo's vault + the shared global store + any
configured custom collection, and a finding routes back to the project it
concerns. Only each child's own
`commit_memory` gates its vault notes; `commit-memories` publishes them from a
temporary worktree as that child's standing memory pull request, while global
lessons go to the dev-bot store's repository (see `devbot:commit-memories`). A
session launched inside a child is unchanged — it searches the child + global,
never the polyrepo.

## Collections

`search-memories` and `reindex-memories` cover the project latent corpus, the
shared global store, and any custom collection configured under
`memory_collections` (project or global config). Each entry is a name mapped to
a `path` and a `semantic` flag; the flag is reserved — both engines are
keyword-only today. See [Configuration](/configuration#memory_collections) for
the shape, precedence, and placeholders.

## Configuration

The vault is published on the owning project's memory pull request when
`commit_memory` is `true` (the default is `false`) in the devbot config. Search engine choice —
`mdctx` (keyword) or `qmd` (BM25 keyword) — is set by `memory_search_provider` in
`.devbot.global.jsonc`; the searched corpora are listed under `memory_collections`.

## See also

- [Polyrepo sessions](/polyrepo-sessions) — how this module scopes itself to the owning project
- [QMD](/modules/agentic/qmd) — the BM25 vault search engine
- [mdctx](/modules/agentic/mdctx) — the keyword vault search engine
- [Configuration](/configuration) — `memory_search_provider`, `memory_collections`, and `commit_memory`
