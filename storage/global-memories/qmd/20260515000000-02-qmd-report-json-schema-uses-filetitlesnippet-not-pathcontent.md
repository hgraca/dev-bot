---
date: 2026-05-15
keywords: ["qmd"]
---

## qmd-report JSON schema uses `file`/`title`/`snippet`, NOT `path`/`content`

When consuming qmd-report's `--format json` output, the result objects use `file` (URI string), `title`, `score`, and `snippet` — NOT `path` or `content`. Calling `r.get("path")` or `r.get("content")` silently returns empty string, producing a blank memory section with only scores visible. To get full file content, call `qmd get <file_uri>` as a separate subprocess. Reference: `gather-context.py` fix commit `773f0b8`. Cross-ref [[patterns]] "Orchestrator tool: compose multiple report tools into one gather-context call".
