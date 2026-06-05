#!/usr/bin/env node
// =============================================================================
// src/agentic/graphify/tools/claudecode/mcp-server.js
// MCP stdio server proxy for graphify.serve (Python MCP server).
// Detects the correct Python interpreter and graph.json path, then execs
// the graphify.serve Python module which handles the full MCP stdio protocol.
//
// Claude Code loads this server via .mcp.json to make graphify MCP tools
// available in the agent's tool palette.
//
// Register in .mcp.json:
//   {
//     "mcpServers": {
//       "graphify": {
//         "command": "node",
//         "args": ["src/agentic/graphify/tools/claudecode/mcp-server.js"]
//       }
//     }
//   }
//
// MCP tools exposed by graphify.serve:
//   graphify_query_graph    — Search graph using BFS/DFS
//   graphify_get_node       — Get full node details
//   graphify_get_neighbors  — Get direct neighbors
//   graphify_get_community  — Get community nodes
//   graphify_god_nodes      — Most connected nodes
//   graphify_graph_stats    — Node/edge/community counts
//   graphify_shortest_path  — Shortest path between concepts
//
// Dependencies: none (Node.js child_process only)
// Python dependency: graphifyy installed via uv (handled by install.sh)
// =============================================================================

const { spawn } = require("child_process")
const path = require("path")
const fs = require("fs")

// ── Path resolution ──────────────────────────────────────────────────────────

const PROJECT_ROOT = (() => {
  // Walk up from script root to find project root (where graphify-out lives)
  let dir = __dirname
  for (let i = 0; i < 10; i++) {
    const candidate = path.resolve(dir, "..", "..", "..", "..", "..")
    if (fs.existsSync(path.join(candidate, "graphify-out")) || fs.existsSync(path.join(candidate, ".git"))) {
      return candidate
    }
    dir = path.resolve(dir, "..")
  }
  return process.cwd()
})()

function readDevbotDir() {
  try {
    const cfgPath = path.join(PROJECT_ROOT, ".devbot.project.jsonc")
    if (!fs.existsSync(cfgPath)) return ".agents"
    const raw = fs.readFileSync(cfgPath, "utf8")
    const stripped = raw.replace(/^\s*\/\/.*$/gm, "")
    return JSON.parse(stripped)?.devbot_dir ?? ".agents"
  } catch { return ".agents" }
}

function findGraphJson() {
  // Look for graph.json in standard locations
  const candidates = [
    path.join(PROJECT_ROOT, "graphify-out", "graph.json"),
    path.join(PROJECT_ROOT, readDevbotDir(), "graphify", "graph.json"),
  ]
  for (const c of candidates) {
    if (fs.existsSync(c)) return c
  }
  return null
}

function findPython() {
  const devbotDir = readDevbotDir()
  // 1. Check for graphify-specific Python via uv
  try {
    const secretsPath = path.join(PROJECT_ROOT, devbotDir, "secrets", "graphify-python")
    if (fs.existsSync(secretsPath)) {
      const python = fs.readFileSync(secretsPath, "utf8").trim()
      if (python && fs.existsSync(python)) return python
    }
    // 2. Check global devbot root
    const devbotRoot = path.resolve(PROJECT_ROOT, devbotDir)
    const globalSecrets = path.join(devbotRoot, "storage", "secrets", "graphify-python")
    if (fs.existsSync(globalSecrets)) {
      const python = fs.readFileSync(globalSecrets, "utf8").trim()
      if (python && fs.existsSync(python)) return python
    }
  } catch {
    // fall through
  }

  // 3. Fallback: use system python3
  return "python3"
}

// ── MCP stdio helpers ────────────────────────────────────────────────────────

function sendMessage(msg) {
  const data = JSON.stringify(msg) + "\n"
  process.stdout.write(data)
}

function recvMessage() {
  return new Promise((resolve) => {
    let buf = ""
    const onData = (chunk) => {
      buf += chunk.toString()
      const idx = buf.indexOf("\n")
      if (idx !== -1) {
        const line = buf.slice(0, idx)
        buf = buf.slice(idx + 1)
        process.stdin.removeListener("data", onData)
        try {
          resolve(JSON.parse(line))
        } catch {
          resolve(null)
        }
      }
    }
    process.stdin.on("data", onData)
  })
}

// ── MCP lifecycle — thin proxy to graphify.serve ────────────────────────────

async function main() {
  const pythonBin = findPython()
  const graphFile = findGraphJson()

  // We act as a stdio proxy to graphify.serve if graph.json exists,
  // otherwise provide a minimal stub that tells the user to build the graph first.

  if (graphFile) {
    // Proxy mode: spawn graphify.serve and bridge stdio
    const child = spawn(pythonBin, ["-m", "graphify.serve", graphFile], {
      stdio: ["pipe", "pipe", "inherit"],
      env: { ...process.env },
    })

    // Bridge stdin: parent stdin -> child stdin
    process.stdin.on("data", (chunk) => {
      child.stdin.write(chunk)
    })
    process.stdin.on("end", () => {
      child.stdin.end()
    })

    // Bridge stdout: child stdout -> parent stdout
    child.stdout.on("data", (chunk) => {
      process.stdout.write(chunk)
    })

    // Wait for child to finish
    await new Promise((resolve) => {
      child.on("exit", () => resolve(undefined))
      child.on("error", () => resolve(undefined))
    })
    return
  }

  // Stub mode: respond with a helpful message when no graph exists
  // Implement minimal MCP protocol so Claude Code gets a clean error
  const init = await recvMessage()
  if (init && init.method === "initialize") {
    sendMessage({
      jsonrpc: "2.0",
      id: init.id,
      result: {
        protocolVersion: "2024-11-05",
        serverInfo: { name: "graphify", version: "1.0.0" },
        capabilities: { tools: {} },
      },
    })
  }
  sendMessage({ jsonrpc: "2.0", method: "notifications/initialized" })

  // Loop and respond to tool requests
  while (true) {
    const msg = await recvMessage()
    if (!msg) continue

    if (msg.method === "tools/list") {
      // Still list tools so the agent knows they exist
      sendMessage({
        jsonrpc: "2.0",
        id: msg.id,
        result: {
          tools: [
            {
              name: "graphify_query_graph",
              description: "Search the knowledge graph using BFS or DFS. Returns relevant nodes and edges as text context.",
              inputSchema: {
                type: "object",
                properties: {
                  question: { type: "string", description: "Natural language question or keyword search" },
                  mode: { type: "string", enum: ["bfs", "dfs"], default: "bfs", description: "bfs=broad context, dfs=trace a specific path" },
                  depth: { type: "integer", default: 3, description: "Traversal depth (1-6)" },
                  token_budget: { type: "integer", default: 2000, description: "Max output tokens" },
                  context_filter: { type: "array", items: { type: "string" }, description: "Edge-context filter, e.g. ['call', 'field']" },
                },
                required: ["question"],
              },
            },
            {
              name: "graphify_get_node",
              description: "Get full details for a specific node by label or ID.",
              inputSchema: {
                type: "object",
                properties: {
                  label: { type: "string", description: "Node label or ID to look up" },
                },
                required: ["label"],
              },
            },
            {
              name: "graphify_get_neighbors",
              description: "Get all direct neighbors of a node with edge details.",
              inputSchema: {
                type: "object",
                properties: {
                  label: { type: "string", description: "Node label to find neighbors for" },
                  relation_filter: { type: "string", description: "Optional: filter by relation type" },
                },
                required: ["label"],
              },
            },
            {
              name: "graphify_get_community",
              description: "Get all nodes in a community by community ID.",
              inputSchema: {
                type: "object",
                properties: {
                  community_id: { type: "integer", description: "Community ID (0-indexed by size)" },
                },
                required: ["community_id"],
              },
            },
            {
              name: "graphify_god_nodes",
              description: "Return the most connected nodes - the core abstractions of the knowledge graph.",
              inputSchema: {
                type: "object",
                properties: {
                  top_n: { type: "integer", default: 10 },
                },
              },
            },
            {
              name: "graphify_graph_stats",
              description: "Return summary statistics: node count, edge count, communities, confidence breakdown.",
              inputSchema: { type: "object", properties: {} },
            },
            {
              name: "graphify_shortest_path",
              description: "Find the shortest path between two concepts in the knowledge graph.",
              inputSchema: {
                type: "object",
                properties: {
                  source: { type: "string", description: "Source concept label or keyword" },
                  target: { type: "string", description: "Target concept label or keyword" },
                  max_hops: { type: "integer", default: 8, description: "Maximum hops to consider" },
                },
                required: ["source", "target"],
              },
            },
          ],
        },
      })
    } else if (msg.method === "tools/call") {
      const name = msg.params.arguments?.name || msg.params.name || ""
      sendMessage({
        jsonrpc: "2.0",
        id: msg.id,
        result: {
          content: [{ type: "text", text: `Graph not found at ${PROJECT_ROOT}/graphify-out/graph.json. Run 'graphify update' first to build the knowledge graph.` }],
          isError: true,
        },
      })
    }
  }
}

main().catch((err) => {
  process.stderr.write(`[graphify MCP] Fatal: ${err.message}\n`)
  process.exit(1)
})
