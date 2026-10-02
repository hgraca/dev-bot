---
date: 2026-10-02
keywords: ["devbot", "memory-vault", "supersession", "search-memories", "frontmatter"]
aliases: ["superseded_by", "supersession banner", "stale decision warning", "de-sargified"]
---

## Supersession is a body banner plus bidirectional frontmatter pointers

A replaced latent note now carries `superseded_by:` (paths relative to its store root) and a standardized body banner immediately after the title, while the replacement carries `supersedes:`. The banner is the load-bearing part: `search-memories` returns each hit with its YAML frontmatter stripped, so a `superseded_by:` key alone is invisible to the reader; the tool was also taught to parse that key and prepend a `> **SUPERSEDED by** …` line, so the warning survives even when an author forgets the banner. A shared `global/` note cannot point at a project-specific memory — the path does not resolve from the global store — so a global note superseded by a project finding must be deleted or rewritten as a global lesson instead. `aliases:` was added alongside as an optional array of synonyms or in-vault coinages that widens matching, since both search engines are keyword/BM25 only. Schema in `devbot:memory-management` §6; parser and notice injection in `src/agentic/memory/tools/search-memories/search-memories.py`.
