---
title: "Memory"
description: "The knowledge vault — recall, session capture, vault structure, pruning, and scratch notes."
commands: ["audit-memory", "prune-memories", "remember-session"]
skills: ["memory-management", "prune-memories", "remember-session", "search-memory", "thinking"]
hooks: ["reindex-memories"]
tools: ["generate-mcp-guide", "reindex-memories", "reindex-passive-memories", "search-memories"]
---

The knowledge vault: what agents learned in earlier sessions, kept where the next session can find it.

## What it does

- **Recall** — `search-memory` looks up past decisions, learnings and gotchas before a problem is solved again.
- **Capture** — `remember-session` promotes what a session learned into the vault and routes each entry by kind.
- **Structure** — `memory-management` defines the vault layout and routing rules; `prune-memories` (skill and command) keeps it from going stale; `thinking` provides scratch files for work in progress.
- **Staying current** — a `file.edited` hook reindexes the vault as it changes, so a search never misses a note written moments ago.

## Session capture

The `remember-session` skill captures what was learned during a session and routes it to the knowledge vault — so the next session starts smarter.

- **Post-commit hook**: after each `git commit`, a trigger file is written
- **Session idle**: when the session goes quiet, `remember-session` fires
- **Learning routing**: findings are categorized —
  - Product decisions → `memory/latent/PDRs/`
  - Architecture decisions → `memory/latent/ADRs/`
  - Gotchas → `memory/latent/global/<tech>/` or `memory/latent/learnings/`
- **Watermark tracking**: only new learnings since the last capture are processed

Say "wrap up", "remember session", or "capture session" to trigger it manually.

## Configuration

The vault is committed with the project by default (`commit_memory` in the devbot config). Search engine choice — `mdctx` (keyword) or `qmd` (hybrid) — is set by `memory_search_provider` in `.devbot.global.jsonc`.

## See also

- [QMD](/modules/agentic/qmd) — the semantic vault search engine
- [mdctx](/modules/agentic/mdctx) — the keyword vault search engine
- [Configuration](/configuration) — `memory_search_provider` and `commit_memory`
