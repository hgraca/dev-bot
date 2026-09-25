---
date: 2026-09-25
keywords: ["codebase-index", "codebase-memory", "codebase_index_provider", "gather-context", "scout"]
---

# Codebase-engine instructions route through the shared slot, never name an engine's tools

The codebase engine is selected at runtime by the global `codebase_index_provider` key — `codebase-index` (Ollama semantic index) or `codebase-memory` (tree-sitter graph). The two modules are mutually exclusive and share ONE skill slot, `devbot:codebase-index` (see `20260923121000-codebase-index-shared-slot-name-is-deliberate.md`). Their MCP tools have nothing in common: `codebase_search`/`codebase_peek`/`implementation_lookup`/`call_graph`/`find_similar` on one side, `search_graph`/`trace_path`/`get_code_snippet`/`get_architecture` on the other. Any instruction that names one engine's tools is therefore wrong on half the flips.

## The trap that bit

`explore/skills/gather-context` step 6 told scout to "use the `codebase-index` MCP tools", and `devteam/agents/scout.md` listed `codebase-index` as one of its MCP tools. The default provider had already moved to `codebase-memory`, so every scout run reached a semantic index with no embedding provider and errored with "No embedding-capable provider found" — findings still arrived, but only via the glob/grep fallback, and the failure was invisible unless reported.

Two independent defects were in play, and fixing one alone would not have surfaced the other:

1. **The instruction named a single engine's tools.** The shared slot exists precisely so references survive the flip; the tool names belong in each engine's own skill.
2. **The retired engine's plugin was still loaded.** A separate wiring bug left `opencode-codebase-index` registered on the second opencode plugin surface, so those tools were genuinely present in the palette rather than absent. See `/global/opencode/` "opencode unions two plugin surfaces…".

## The rule

- Agent instructions and workflow skills reference `devbot:codebase-index` — the slot — and let that skill name the tools. Do not name an engine or its tools in a routing instruction.
- Per-engine tool names may appear only when explicitly labelled per engine (as `explore/skills/search-code` does to contrast them), never as the general route.
- This mirrors the memory-search precedent: no instruction names `qmd`/`mdctx`; everything routes via `search-memories` (ADR `20260907140000-mdctx-memory-search-engine-swap`).

## Enforcement

`src/_shared/tests/codebase-engine-references_tests.bats` guards it: it asserts `gather-context`, `search-code` and `scout.md` all reference `devbot:codebase-index`, bans engine-specific tool names in `gather-context`/`scout.md`, and bans the verbatim "`<engine>` MCP tools" phrasing across all three. The ban list is matched in backticks so prose like "call graph" cannot trip it, and a vacuity test fails if a fixture is renamed or the token list shrinks. Verified to fail against the pre-fix content.
