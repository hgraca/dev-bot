# Graphify — OpenCode integration

Expose graphify CLI commands as OpenCode custom tool.

## Registration

Register `tools/opencode/graphify.ts` in your OpenCode tools configuration:

```json
{
  "tools": [
    {
      "name": "graphify",
      "description": "Codebase knowledge graph tool",
      "source": "src/agentic/graphify/tools/opencode/graphify.ts"
    }
  ]
}
```

## Usage

OpenCode tool accepts these parameters:

| Parameter | Required    | Description                                                                  |
| --------- | ----------- | ---------------------------------------------------------------------------- |
| `command` | yes         | Subcommand: `query`, `path`, `explain`, `update`, `graph-stats`, `god-nodes` |
| `query`   | for query   | Natural language question for graph traversal                                |
| `dfs`     | no          | Set to `"true"` for depth-first search                                       |
| `source`  | for path    | Source concept name                                                          |
| `target`  | for path    | Target concept name                                                          |
| `node`    | for explain | Node name to explain                                                         |

## Example invocations

```
graphify command=query query="how does authentication work"
graphify command=path source="AuthModule" target="Database"
graphify command=explain node="UserController"
graphify command=update
graphify command=graph-stats
graphify command=god-nodes
```

## Requirements

- `graphify` CLI installed (`uv tool install graphifyy --with mcp`)
- built knowledge graph at `graphify-out/graph.json`
- Bun runtime (for TypeScript tool execution)
