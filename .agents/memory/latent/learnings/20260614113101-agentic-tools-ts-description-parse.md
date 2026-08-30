---
date: 2026-06-14
keywords: ["devbot", "agentic-tools", "typescript", "description", "parsing", "gotcha"]
---

# TypeScript tool description extraction gotcha

When extracting descriptions from `tool({...})` exports in `.opencode/tools/*.ts`, the description can be either a single multi-line string literal (tree.ts, format-md.ts, search-memories.ts) or a concatenated string with `+` operators across multiple lines (agent-communication.ts, graphify.ts). A Python regex must match both patterns: `description:\s*\n(\s*"(?:\\.|[^"\\])*"(?:\s*\+\s*\n\s*"(?:\\.|[^"\\])*")*)`. Description strings may contain `"|"` characters that must be escaped for markdown table output. The `args: {}` pattern is required (Zod schemas crash opencode's `toJsonSchema` at load time, documented in create-opencode-tool SKILL.md). Tool files under `.opencode/tools/` are symlinks that need `-L` / `readlink` handling in bash loops — use `find -L .opencode/tools/ -name '*.ts'` or `for f in .opencode/tools/*.ts; do [ -f "$f" ] && ...` to avoid failures on broken symlinks.
