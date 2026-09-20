---
date: 2026-09-07
keywords: ["mdctx", "keyword extraction", "literal search", "context-index"]
trigger-on: ["mdctx-literal-search-miss"]
---

## mdctx keyword-cap drops exact literal tokens — search returns nothing for identifiers

mdctx's per-file keyword extraction is auto-sized to 5–25 keywords (roughly one
per 30 words, RAKE-style). An exact distinctive literal in a note's body — an
error code, a hyphenated compound, a slug, an identifier — is frequently never
selected as a keyword, so `mdctx search` (and dev-bot's `search-memories`
under the mdctx engine) returns **zero hits** for it, even though the term is
verbatim in the file. Natural-language phrases and titles match fine. Search
only ranks against the extracted keyword set, not full raw text (verified
against mdctx 0.1.0: the raw CLI also returns "No matches"). dev-bot's
`search-memories` wrapper closes this with a bounded full-text substring
fallback when the keyword index misses (raw `mdctx search` has no fallback);
qmd (`memory_search_provider: "qmd"`) covers full content natively.
