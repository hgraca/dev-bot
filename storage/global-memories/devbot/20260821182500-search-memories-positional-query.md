---
date: 2026-08-21
keywords: ["devbot", "search-memories", "cli", "argparse"]
---

## search-memories CLI takes positional queries, not --query

The `search-memories` bash wrapper (`src/agentic/memory/tools/search-memories/search-memories.sh`) accepts the search query **positionally**, not via a `--query` flag. The `--query` flag is only understood by the underlying `search-memories.py`; the `.sh` wrapper's argument parser treats `--query` as an opaque `--*` passthrough and never consumes a value for it, so `search-memories --query "foo"` sends a bare `--query` (no value) to the python script and fails with `argument --query: expected one argument`. Invoke as `search-memories "<query>" [--collection X] [--max-results N]` (or via the MCP tool's positional `args`). The `remember-session` skill still documents the `--query` form — a doc/tool mismatch to correct.
