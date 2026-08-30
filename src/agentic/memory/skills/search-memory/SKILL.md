---
name: devbot:search-memory
description: "Search memory about past learnings, decisions, and technology, and understand codebase relationships, patterns, and architecture. Use this skill whenever you need to recall past context, decisions, or solutions before solving a problem."
---

# Search Memory

Use when you need to search memory about passed learnings, decisions, technology, and the codebase relationships, patterns and architecture.

When you need information, use right tool for question type:

| Question type                                  | Tool                                         |
| ---------------------------------------------- | -------------------------------------------- |
| Reusable lessons (tech-specific)               | Use `search-memories` tool                   |
| Project-specific lessons                       | Use `search-memories` tool                   |
| Product decisions + stakeholder answers (PDRs) | Use `search-memories` tool                   |
| Architectural/technical decisions (ADRs)       | Use `search-memories` tool                   |
| Memory semantic search ("did we ever...?")     | Use `devbot:qmd` skill                              |
| Architecture, relationships, god nodes         | Use `devbot:graphify` skill                         |
| Code by meaning ("find auth logic")            | Use the `codebase-index` MCP (ask naturally) |

If `search-memories` returns no matches, the index may not be built yet or a reindex may still be running — do **not** loop reindex → search → reindex. Check `reindex-memories status` (or `qmd status`); if a reindex is `in_progress`, wait and re-search once. Repeated `reindex-memories` calls coalesce into a single job — they don't make results appear faster.
