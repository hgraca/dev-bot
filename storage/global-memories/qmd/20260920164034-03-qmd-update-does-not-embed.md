---
date: 2026-09-20
keywords: ["qmd", "embed", "update", "index"]
---

## `qmd update` indexes but does not embed — `qmd embed` is a separate step

`qmd collection add` plus `qmd update` only scan and register content in the index; `qmd update` finishes by printing `Run 'qmd embed' to update embeddings (N unique hashes need vectors)` and stops there, leaving vector generation to the separate `qmd embed` command. A test or workflow that calls only `update` therefore exercises the **lexical** path and costs the same (~0.55 s on a tiny collection) whether the index is warm or cold and whether or not an embedding backend such as `ollama` is reachable. So before treating an "end-to-end qmd search" suite as embedding-bound work, check which subcommand it actually runs — and to verify embeddings are in play at all, confirm `qmd embed` executed rather than that `qmd` is installed.
