---
date: 2026-09-07
keywords: ["mdctx", "context-index", "MDCTX_INDEX", "symlinks", "git hooks"]
trigger-on: ["mdctx-mcp-registration", "mdctx-index-location"]
---

## mdctx engine contract: no symlinks, MDCTX_INDEX env, never run `mdctx init`

mdctx (zachkepe/mdctx, npm 0.1.0) has several non-obvious integration traps.
`mdctx build` does NOT follow symlinks — a docs tree reached only via a
symlinked subdir is silently skipped, so each real corpus needs its own
`build`/index (like qmd's separate global collection). The index location is
fully decoupled from the docs root: `mdctx build <dir> -o <index>` writes the
flat `context-index.json` anywhere, `mdctx search -i <index>` reads any index,
and the MCP server honours `MDCTX_ROOT` (docs root) + `MDCTX_INDEX` (index
path) env — set both so `search_context`'s auto-heal rebuild writes to a
gitignored location instead of dropping `context-index.json` into the docs
root. Without env, `mdctx-mcp` roots at `process.cwd()` and writes the index
into the consumer project root. `mdctx search --json` returns
`[{"path","title","score","matchedKeywords"}]` with `path` root-relative and no
snippet/docid — bodies are plain file reads. Finally, NEVER run `mdctx init`:
it installs git hooks + a GitHub Actions workflow into the project; use
`mdctx build` explicitly (engine auto-config commands are dev-bot policy).
