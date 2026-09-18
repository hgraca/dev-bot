---
date: 2026-09-18
keywords: ["search-memories", "memory-index", "stale-index"]
---

# search-memories can return no matches for terms that exist in the vault

Seen twice in the 2026-09-18 session: `search-memories` returned "no matches" for keyword sets whose terms are plainly present in latent notes — a scout query on `tools-grades`/`grade-tools` found nothing while a direct grep located `latent/PDRs/20260918122005-01-grade-tools-tool-evaluation-matrix.md`; other queries in the same session returned hits. Both memory engines are keyword-only (BM25) and the index is rebuilt out of band, so an empty result means "not in the index", not "not in the vault". Before concluding a topic is undocumented, grep `.agents/memory/`, and check `reindex-memories status` (if `in_progress`, wait and re-search once — repeated reindex calls coalesce into one job). The quality issue itself is still open: it is not yet known whether the misses come from stale/incomplete indexing, tokenisation of hyphenated or colon-prefixed terms, or the `--query` handling.
