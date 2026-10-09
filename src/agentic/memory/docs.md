---
title: "Memory"
description: "The knowledge vault — recall, session capture, vault structure, pruning, and scratch notes."
commands: ["audit-memory", "prune-memories", "remember-session"]
skills: ["memory-management", "prune-memories", "reconcile-work", "remember-session", "search-memory", "thinking"]
hooks: ["reindex-memories"]
tools: ["generate-mcp-guide", "reindex-memories", "reindex-passive-memories", "search-memories"]
---

The knowledge vault: what agents learned in earlier sessions, kept where the next session can find it.

## What it does

- **Recall** — `search-memory` looks up past decisions, learnings and gotchas before a problem is solved again.
- **Capture** — `remember-session` promotes what a session learned into the vault and routes each entry by kind.
- **Structure** — `memory-management` defines the vault layout and routing rules; `prune-memories` (skill and command) keeps it from going stale; `reconcile-work` aligns the work-folder states (`todo` → `active` → `archive`) at wrap-up; `thinking` provides scratch files for work in progress.
- **Staying current** — a `file.edited` hook reindexes the vault as it changes, so a search never misses a note written moments ago.

## Session capture

The `remember-session` skill captures what was learned during a session and routes it to the knowledge vault — so the next session starts smarter.

- **Finish flow**: the primary agent runs `remember-session` once when the work is confirmed finished, before `[FINISHED]`
- **Learning routing**: findings are categorized —
  - Product decisions → `memory/latent/PDRs/`
  - Architecture decisions → `memory/latent/ADRs/`
  - Gotchas → `memory/latent/global/<tech>/` or `memory/latent/learnings/`
- **Watermark tracking**: only new learnings since the last capture are processed

Say "wrap up", "remember session", or "capture session" to trigger it manually.

## Supervisor sessions

A project with `supervisor: true` runs sessions across the managed projects
registered in `.devbot.global.jsonc::projects`. Memory is scoped by the files
the session touches: `search-memories --focus <path>` searches the touched
project's vault + the supervisor's vault + the shared global store, and a
finding routes back to the project it concerns. Each child's own
`commit_memory` and `worktrees` govern its memory commits. A session launched
inside a child is unchanged — it searches the child + global, never the
supervisor.

## Configuration

The vault is committed with the project by default (`commit_memory` in the devbot config). Search engine choice — `mdctx` (keyword) or `qmd` (hybrid) — is set by `memory_search_provider` in `.devbot.global.jsonc`.

## See also

- [QMD](/modules/agentic/qmd) — the semantic vault search engine
- [mdctx](/modules/agentic/mdctx) — the keyword vault search engine
- [Configuration](/configuration) — `memory_search_provider` and `commit_memory`
