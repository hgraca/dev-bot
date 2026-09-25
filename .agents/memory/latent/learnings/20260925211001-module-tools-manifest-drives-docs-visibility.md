---
date: 2026-09-25
keywords: ["devbot", "docs", "tools-manifest", "gatherer", "mcp.sh"]
---

# A module's `tools:` front-matter is what makes its tool appear in the docs

## The trap

`src/agentic/docs/tools/gather-module-docs.py` renders a module page's Contents and the aggregate tables from the **declared** `docs.md` capability manifest: `render_contents()` iterates `capabilities["tools"]`, not the discovered files. `capability_details()` does find a flat `tools/<name>.sh` and takes its purpose from the file's `# description:` header — but that detail is rendered only when the front matter declares the tool. Dropping `tools: ["refactor"]` therefore removed the tool from the module page and zeroed its `T` count in `module-reference.md`, even though `tools/refactor.sh` existed with a description header.

Only `*.mcp.sh` reach the MCP aggregate — `mcp_tool_entries()` globs that suffix — so a module's `tools:` list is **broader** than "MCP tools".

## The rule

A module that ships a tool must list it under `tools:` in `docs.md`; the tool lives flat at `tools/<name>.sh` (the gatherer reads `entry.name.split(".")[0]` and quotes its `# description:` header) or at `tools/<name>/` containing an `*.mcp.sh`. Omitting the manifest entry hides the tool site-wide with no test catching it.
