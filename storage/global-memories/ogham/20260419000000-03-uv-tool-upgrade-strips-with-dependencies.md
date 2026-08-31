---
date: 2026-04-19
keywords: ["ogham", "mcp"]
---

## `uv tool upgrade` strips `--with` dependencies

When ogham-mcp is upgraded via `uv tool upgrade ogham-mcp`, any extra packages installed via `--with prefab-ui` are dropped. The update script must re-run `uv tool install "ogham-mcp[postgres,rerank]" --with prefab-ui` after every upgrade. Same pattern applies to any `uv tool install` with `--with` dependencies.
