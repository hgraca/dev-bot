---
tags: [bootstrap, mcp]
description: MCP server tool selection and usage guide
---

# MCP Servers

## Tool Selection

- **chrome-devtools**: Use when you need to debug or inspect a live page in a real browser — pull console errors, network requests, performance traces, or the rendered DOM; reach for this to diagnose _why_ a page misbehaves, not to drive it.
- **codebase-index**: Use to semantically search a large or unfamiliar repo — locate the relevant files, symbols, or definitions before editing, instead of grepping blindly or guessing paths.
- **context7**: Use to fetch current, version-accurate documentation for a library or framework before writing code against it — prevents reliance on stale or hallucinated APIs.
- **devbot-tools**: Use to run dev-bot's own tooling — memory search (`search-memories`), git state (`git-report`), formatting (`format-md/json/yml`), `reindex-memories`, `agent-communication`, `lint-k8s`, `list-projects`, `use-case-map`; the load-bearing custom server for dev-bot workflows.
- **graphify**: Use to search and analyze code structure — trace relationships, dependencies, call graphs, and references to understand how parts of the codebase connect and what an edit will affect.
- **jetbrains**: Use to query and drive the local JetBrains IDE — modules, open files, symbols, call analysis, inspections, and running code via run configurations (e.g. `get_project_modules`, `search_symbol`, `lint_files`); reach for it when the task benefits from the IDE's own indexer or needs something run in the IDE.
- **playwright**: Use to _drive_ a browser programmatically — automate multi-step flows, run end-to-end tests, fill forms, or scrape content that requires interaction; the action tool to chrome-devtools' inspection tool.
- **qmd**: Use to search a local markdown knowledge base (notes, docs, transcripts) — hybrid keyword + semantic search with LLM reranking; reach for it to retrieve written knowledge, then fetch full documents by file. Use when you need to search your memories.
- **websearch**: Use to retrieve current, real-world information beyond your knowledge cutoff — news, latest versions, prices, or any fact that may have changed.
