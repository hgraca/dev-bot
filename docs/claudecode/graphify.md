# Graphify — Claude Code integration

Expose codebase knowledge graph to Claude Code via MCP server that wraps `graphify.serve`.

## Registration

Add to `.mcp.json` at your project root:

```json
{
  "mcpServers": {
    "graphify": {
      "command": "node",
      "args": ["src/agentic/graphify/tools/claudecode/mcp-server.js"]
    }
  }
}
```

## How it works

MCP server (`tools/claudecode/mcp-server.js`) has two modes:

1. **Proxy mode** (default): When `graphify-out/graph.json` exists, it spawns `graphify.serve` (Python MCP server) and bridges stdio. All MCP tools are handled by native Python server.

2. **Stub mode**: When no graph exists, Node.js wrapper provides minimal MCP server that advertises all tool names and responds with helpful message telling user to run `graphify update` first.

## Available tools

Claude Code agents can call these tools after connection:

| Tool                     | What it does                                        |
| ------------------------ | --------------------------------------------------- |
| `graphify_query_graph`   | Search with BFS (broad) or DFS (specific path)      |
| `graphify_get_node`      | Details for node by label or ID                     |
| `graphify_get_neighbors` | Direct neighbours with edge metadata                |
| `graphify_get_community` | All nodes in community                              |
| `graphify_god_nodes`     | Top 10 most-connected nodes                         |
| `graphify_graph_stats`   | Node/edge/community counts and confidence breakdown |
| `graphify_shortest_path` | Shortest path between two concepts                  |

## Requirements

- Node.js (for MCP wrapper)
- `graphify` CLI installed (`uv tool install graphifyy --with mcp`)
- built knowledge graph (`graphify-out/graph.json`)
- Python 3 (for `graphify.serve`)
