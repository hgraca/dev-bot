---
date: 2026-09-18
keywords: ["mdctx", "index", "stale", "branch", "latent"]
trigger-on: ["mdctx-index", "search-memories-stale", "body-not-fetched"]
---

## The mdctx project index is per-working-copy, so switching branches leaves stale entries

`.mdctx/context-index.json` is listed in `.git/info/exclude`, so there is one index per working copy rather than one per branch — yet `.agents/memory/latent/**` IS tracked and therefore differs between branches. Build the index while on branch A, switch to branch B, and every `latent/` note that exists only on A stays in the index although it has vanished from disk; nothing re-indexes on branch switch. The symptom is that a search matches the entry by its indexed title and keywords and then reports `_Error reading file <path>: body not fetched_`, because entries store only path, title, keywords, hash and updatedAt — never the body — so a vanished file yields a fetch error rather than a missing result. Before concluding a note was lost, check whether it is committed elsewhere (`git ls-tree -r --name-only <other-branch> -- .agents/memory/latent`, or `git log --all --oneline -- <path>`): the usual truth is that it lives on another branch, so switching branches is the fix rather than recovery. The previously documented cause — a rebase rewinding the branch — is only one instance of this; the branches simply differing is the general case. Reindexing clears it, but be aware `reindex-memories prune` currently launches a full rebuild instead of the cheap self-heal it advertises.
