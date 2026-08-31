---
date: 2026-04-19
keywords: ["ogham", "mcp"]
---

## prefab-ui as a `--with` dependency for ogham-mcp dashboards

`prefab-ui` is not an ogham extras group (no `ogham-mcp[ui]` exists). It must be installed as a separate `--with` package: `uv tool install "ogham-mcp[postgres,rerank]" --with prefab-ui`. Both `src/tools/ogham/install.sh` and `src/tools/ogham/update.sh` must handle this, because `uv tool upgrade` strips `--with` packages.
