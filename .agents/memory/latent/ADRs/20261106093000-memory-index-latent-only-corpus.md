---
date: 2026-11-06
keywords: ["memory-index", "latent", "corpus", "search-memories", "mdctx"]
aliases: ["passive memories only", "work notes not searchable"]
see: ["ADRs/20260919120352-branch-aware-memory-index.md", "ADRs/20261009084426-polyrepo-memory-scope-resolution.md"]
---

## Memory search indexes only the latent corpus

`search-memories` indexes `<devbot-dir>/memory/latent` for the project collection, not the whole memory tree. `af067a54` widened it to `memory/` so `work/` and `thinking/` notes were searchable as soon as they were written, but in a 28-repo workspace that buried durable knowledge under archived backlogs and review dumps: a two-token BM25 query returned ~20k chars of plan material, and archived backlog files were top hits for unrelated terms. Scope is set once in `src/_shared/memory_collections.py` — the resolver both the build and the query path use — so mdctx, qmd and the compatibility fallbacks cannot disagree; `work/`, `thinking/` and `active/` are searchable only through an explicitly registered custom collection, while the shared global store and `memory_collections` entries are unchanged. Existing indexes rebuild once: the branch record carries `corpus: "latent"` and any other value forces an `--ensure` rebuild, while `_index_corpus_root` still reads a legacy whole-memory index correctly until that rebuild. Two migration guards fail closed rather than record a latent corpus while a whole-memory qmd collection survives: the reindex engine migrates the project collection before its missing-path skip, and `qmd init` creates the missing latent directory (or refuses when it cannot). The trade-off is deliberate — a plan note written five minutes ago is no longer recallable by search; it is read from `work/active/`, which is where a live plan belongs.
