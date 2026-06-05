---
date: 2026-04-17
keywords: ["graphify", "graph"]
---

## `uv tool install` creates isolated venvs — system python can't import installed packages

When `graphifyy` is installed via `uv tool install graphifyy`, the system `python3` can't `import graphify` because `uv` creates an isolated venv. The MCP server (`python3 -m graphify.serve`) must use the venv's Python interpreter, not the system one. Resolved by storing the venv Python path in `storage/secrets/graphify-python` at install time. ADR-002.
