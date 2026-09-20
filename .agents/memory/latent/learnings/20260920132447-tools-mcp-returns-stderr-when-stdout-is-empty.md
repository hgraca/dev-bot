---
date: 2026-09-20
keywords: ["tools-mcp", "mcp", "stderr", "search-memories"]
---

# The devbot-tools server now returns a tool's stderr when stdout is empty

`start-tools-mcp.ts` returned stdout only on a clean exit and discarded stderr, so a tool that fails open — exits 0 with a `WARN:` on stderr and nothing on stdout — was reported as `Tool '<name>' completed successfully.` with an empty result, hiding the only explanation the agent could act on. That is the shape `search-memories` takes when it cannot refresh a stale memory index, which is why it appeared to silently return nothing.

The fix returns stderr when stdout is empty, while a non-empty stdout is still passed through untouched so a `--json` payload is never polluted. The contract is recorded in `tools-mcp/skills/tools-mcp/SKILL.md` under "Output contract". When a tool looks like it returned nothing, read its stderr — and note the remaining limit: a warning that accompanies _partial_ results is still not surfaced to the agent.
