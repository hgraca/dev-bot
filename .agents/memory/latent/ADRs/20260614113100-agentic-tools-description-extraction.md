---
date: 2026-06-14
keywords: ["devbot", "agentic-tools", "typescript", "description", "extraction"]
see: ["project/20260614113300-format-md-pipe-mode-in-bash.md"]
---

## ADR: Tool description extraction from TypeScript tool definitions

The `devbot agentic-tools` subcommand needs to extract tool descriptions from `.opencode/tools/*.ts` files. These files export `tool({ description: "...", args: {}, async execute(...) {...} })`. Description extraction must handle two patterns: single multi-line string literals (tree.ts, format-md.ts, search-memories.ts) and string concatenation with `+` operators (agent-communication.ts, graphify.ts). Both use `args: {}` (empty object) to avoid Zod schema crash at load time.

Implementation uses inline Python with a regex approach: match `description:\s*\n` followed by one or more `"..."` string literals (possibly chained with `+\n`), extract each quoted string content, join, and decode escape sequences. Descriptions include `\n\nParameters:\n- param (type): desc` sections with inline parameter docs that are used to generate the "how-to" column. Extraction is done at display time (not persisted) since the tool files are stable symlinks into `src/agentic/<module>/tools/`. The table output is piped through `format-md.py` for column alignment.
