---
date: 2026-04-16
keywords: ["ogham", "mcp"]
---

## M-ARCH-003: Centralized MCP configuration via shared opencode.jsonc

DevBot manages 7 MCP servers (websearch, context7, grep_app, git, ast-grep, ogham, codebase-index, obsidian) across multiple projects
Store all MCP configs in a single shared file (storage/opencode.jsonc) and symlink it from each project. Use opencode.upsert_mcp in per-tool install scripts to register MCP blocks. This avoids per-project duplication and enables centralized updates.
