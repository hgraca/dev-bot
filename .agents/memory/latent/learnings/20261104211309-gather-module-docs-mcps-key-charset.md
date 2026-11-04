---
date: 2026-11-04
keywords: ["gather-module-docs", "mcps", "front-matter", "docs"]
---

# `mcps:` front-matter keys must match `[A-Za-z0-9_-]+`

`gather-module-docs.py` parses front matter with `FM_LINE = ^([A-Za-z0-9_-]+):`, so a nested `mcps:` key containing quotes or angle brackets (`"netsuite-<account_id>"`) is silently dropped: the module page loses its capability strip and Contents section, `docs/mcps.md` gets no row, and `module-reference.md` shows `—` for MCP. Declare the placeholder with only allowed characters (`netsuite-account_id`) and explain the real `<id>` suffix in the page body.
