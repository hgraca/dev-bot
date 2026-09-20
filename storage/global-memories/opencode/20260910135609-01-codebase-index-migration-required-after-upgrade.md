---
date: 2026-09-10
keywords: ["opencode", "codebase-index", "INDEX_UNAVAILABLE", "migration"]
trigger-on: ["codebase-index-index-migration", "mcp-retrieval-unavailable"]
---

## codebase-index retrieval fails with INDEX_UNAVAILABLE after a package upgrade

`opencode-codebase-index` namespaces its on-disk index schema per branch catalog: metadata keys `index.callGraphResolutionVersion.<catalog>`, `index.parser.swiftVersion.<catalog>`, `index.parser.metalVersion.<catalog>`, `index.symbolExtractorVersion.<catalog>`, where `<catalog>` is a 16-char hash shared with `file-hashes.<catalog>.json`. A package upgrade that bumps any of those expected constants makes `getIndexFreshness()` return `reason: "migration-required"`, which blocks every retrieval tool with `INDEX_UNAVAILABLE` until the index is rebuilt — even though `cbi status` / `index_status` still reports "Compatibility: Index is compatible" (that check only covers provider/model, not the migration versions). The package's incremental auto-index does NOT perform the migration; run `cbi index` (or MCP `index_codebase`) — it migrates without `--force` and is a cheap no-op when current. Diagnosing this is harder than it should be because the MCP adapter's `operationErrorResult` only forwards `ReportedToolError.safeText`; the precise reason carried by `AutoIndexRetrievalUnavailableError` is dropped and replaced by the generic `INDEX_UNAVAILABLE: Call index_status...`. Run the package's CLI directly (`cbi search "<q>"`) to see the real reason.
