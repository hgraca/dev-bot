# Gotcha: Custom opencode tools are NOT inherited by subagent tasks

The `search-memories` custom tool (defined in `src/instructions/tools/search-memories/search-memories.ts`) is available to the orchestrator via the tool list but is NOT available to subagents spawned via the `Task` tool.

## Symptom

Scout agent (or any subagent) tries to call `search-memories` as an MCP tool, fails, falls back to running the Python script directly at an incorrect path (`.opencode/skills/devbot/memory/_tools/qmd/search-memories.py` instead of `src/instructions/tools/search-memories/search-memories.py`).

## Fix

Update the skill/instruction that subagents use to provide a correct bash fallback path. In `gather-context/SKILL.md`:

```
If the `search-memories` tool is available, call it with the given keywords.
Otherwise, fall back to running the script directly:
python3 src/instructions/tools/search-memories/search-memories.py ...
```

## Root cause

Custom opencode tools (`.ts` files in `src/instructions/tools/`) registered in the tool list are only injected into the orchestrator agent's context. Subagent tasks get a fresh tool set that only includes built-in tools plus MCP servers registered in `opencode.jsonc`. They do NOT inherit custom tools.

## Options to make tools universally available

1. Register as MCP server in `opencode.jsonc` — but MCP protocol differs from simple scripts
2. Provide bash fallback in subagent instructions (current approach)
3. Register as an opencode command (in `src/instructions/commands/`) — subagents CAN use commands
