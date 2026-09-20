---
date: 2026-09-15
keywords: ["mdctx", "reindex-memories", "thinking", "body-not-fetched", "latent"]
trigger-on: ["mdctx-index-scope", "search-memories-no-results", "search-memories-body-not-fetched"]
---

## mdctx memory index covers `latent/` only — `thinking/` is unsearchable by design

The devbot memory pipeline (`reindex-memories` with `memory_search_provider=mdctx`) builds exactly **two** indexes: the project index from `<project>/.agents/memory/latent`, and the global index from `storage/global-memories`. Nothing else in the vault is indexed. `thinking/` (scratch drafts) and `work/` (plans, backlogs) are deliberately outside the search surface — they are local, gitignored artifacts, with `thinking/` added to `.git/info/exclude`.

The consequence is a recurring false diagnosis. When a topic's only write-up lives in `thinking/`, a search returns nothing or off-topic hits, which looks like a stale or broken index. It is neither. `reindex-memories` cannot help, and the skill explicitly warns against looping `reindex → search → reindex`. The fix is to promote the draft to `latent/`, reindex, and it becomes searchable. Before concluding an index is stale, check where the content actually lives: if it is in `thinking/` or `work/`, no rebuild will ever surface it.

A second symptom points the other way. When a `latent/` file is deleted or moved while its index entry survives — a rebase rewinding the branch is the common cause — search matches the entry by its indexed title and keywords, then fails to read the body and returns `_Error reading file <path>: body not fetched_`. That message means the index holds a **stale entry for a file that no longer exists**; it is not a tool failure and not a corrupt index. Either restore the file (for example `git cherry-pick` the orphaned commit out of the reflog) or reindex so the stale entry is dropped. Index entries store only `path`, `title`, extracted `keywords`, a `hash`, and `updatedAt` — never the body — which is precisely why a vanished file yields a fetch error rather than a missing result.
