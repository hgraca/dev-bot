---
date: 2026-10-02
keywords: ["devbot", "memory", "reindex", "global-memories", "hooks"]
trigger-on: ["global-memory-note-not-searchable", "reindex-memories-hook"]
aliases: ["new global note invisible to search", "reindex-memories after global write"]
---

## A new note in the shared global store is not auto-reindexed

The memory module's only `file.edited` hook matches `/memory/latent/.*\.md$` (`src/agentic/memory/hooks.json`), so writing a note under `storage/global-memories/` — the shared store every project's `latent/global` symlinks to — triggers no reindex. The note is invisible to `search-memories` until `reindex-memories` is run explicitly; query-time `--ensure` does not cover it, because the branch record hashes the project vault, not the shared store. This surfaced while adding a `mysql/` note that a follow-up search could not find although the file was on disk and committed — a keyword search returned only project-store hits, and the note appeared at once after an explicit `reindex-memories`. After adding or editing a global note, run `reindex-memories`.
