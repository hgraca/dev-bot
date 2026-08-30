#!/usr/bin/env bash
# =============================================================================
# src/agentic/graphify/tools/graphify.sh
# CLI wrapper for the graphify tool — codebase knowledge graph introspection.
#
# Usage:
#   graphify.sh query "question"            # BFS traversal — broad context
#   graphify.sh query "question" --dfs      # DFS — trace specific path
#   graphify.sh path "A" "B"                # shortest path between concepts
#   graphify.sh explain "X"                 # explain a node and its connections
#   graphify.sh update                      # update graph for current project
#   graphify.sh graph-stats                 # node/edge/community counts
#   graphify.sh god-nodes                   # most connected nodes
#   graphify.sh --help                      # show help
#   echo "..." | graphify.sh query stdin    # pipe query from stdin
#
# Output format: Markdown (unless piped, then plain text)
# Dependencies: graphify CLI (installed via uv tool install graphifyy --with mcp)
#
# Parameters:
# - command (string, required): one of query, path, explain, update, graph-stats, god-nodes
# - query (string, optional): natural language question for BFS traversal
# - source (string, optional): source node for path command
# - target (string, optional): target node for path command
# - node (string, optional): node name to explain
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Help ──────────────────────────────────────────────────────────────────────

show_help() {
  cat <<'HELP'
Usage: graphify.sh <command> [options]

Commands (delegated to graphify CLI):
  query "<question>"     BFS traversal — broad context search
  query "<question>" --dfs   DFS — trace specific path
  path "A" "B"           shortest path between two concepts
  explain "X"            explain a node and its connections
  update                 update knowledge graph for current project
  graph-stats            show node/edge/community counts (via MCP)
  god-nodes              show most connected nodes (via MCP)

Output: Markdown format (plain text when piped)

Examples:
  graphify.sh query "authentication flow"
  graphify.sh path "User" "Database"
  graphify.sh explain "AuthModule"
  graphify.sh update
HELP
}

# ── Detect pipe mode ──────────────────────────────────────────────────────────

is_pipe() {
  [[ ! -t 0 ]]
}

# ── Graph file helpers ────────────────────────────────────────────────────────

find_graph_file() {
  # Look for graph.json in standard locations
  if [[ -f "graphify-out/graph.json" ]]; then
    echo "graphify-out/graph.json"
  elif [[ -f ".ai/graphify/graph.json" ]]; then
    echo ".ai/graphify/graph.json"
  else
    echo ""
  fi
}

# ── Query graph.json directly (for stats/god-nodes) ──────────────────────────

query_graph_json() {
  local graph_file="$1"
  local query_type="$2"

  if [[ ! -f "$graph_file" ]]; then
    echo "FATAL: graph.json not found. Run 'graphify.sh update' first." >&2
    exit 1
  fi

  case "$query_type" in
    graph-stats)
      python3 -c "
import json, sys
with open('$graph_file') as f:
    data = json.load(f)
nodes = len(data.get('nodes', []))
edges = len([e for e in data.get('links', []) if isinstance(e, dict)])
print(f'**Graph Statistics**')
print(f'')
print(f'| Metric | Count |')
print(f'|--------|-------:|')
print(f'| Nodes  | {nodes} |')
print(f'| Edges  | {edges} |')
"
      ;;
    god-nodes)
      python3 -c "
import json, sys
from collections import Counter
with open('$graph_file') as f:
    data = json.load(f)
nodes = {n['id']: n for n in data.get('nodes', [])}
links = [e for e in data.get('links', []) if isinstance(e, dict)]
adj = Counter()
for e in links:
    adj[e.get('source', '')] += 1
    adj[e.get('target', '')] += 1
top = adj.most_common(10)
print(f'**Top 10 Most Connected Nodes**')
print(f'')
print(f'| Node | Connections |')
print(f'|------|------------:|')
for nid, count in top:
    label = nodes.get(nid, {}).get('label', nid)
    print(f'| {label} | {count} |')
"
      ;;
  esac
}

# ── Main dispatch ─────────────────────────────────────────────────────────────

main() {
  if [[ $# -eq 0 ]]; then
    show_help
    exit 0
  fi

  local cmd="${1:-}"
  shift || true

  case "$cmd" in
    --help|-h)
      show_help
      ;;

    query)
      if [[ $# -eq 0 ]] && is_pipe; then
        # Pipe mode: read query from stdin
        local question
        question="$(cat | tr -d '\n')"
        if [[ -z "$question" ]]; then
          echo "FATAL: query requires a question as argument or piped input." >&2
          exit 1
        fi
        exec graphify query "$question"
      elif [[ $# -ge 1 ]]; then
        local question="$1"
        shift
        exec graphify query "$question" "$@"
      else
        echo "FATAL: query requires a question as argument or piped input." >&2
        exit 1
      fi
      ;;

    path)
      if [[ $# -lt 2 ]]; then
        echo "FATAL: path requires two arguments: source and target." >&2
        exit 1
      fi
      exec graphify path "$@"
      ;;

    explain)
      if [[ $# -lt 1 ]]; then
        echo "FATAL: explain requires a node name." >&2
        exit 1
      fi
      exec graphify explain "$1"
      ;;

    update)
      echo "## Updating Knowledge Graph"
      echo ""
      exec graphify update .
      ;;

    graph-stats|god-nodes)
      local graph_file
      graph_file="$(find_graph_file)"
      if [[ -z "$graph_file" ]]; then
        echo "## No graph found"
        echo ""
        echo "Run \`graphify.sh update\` first to build the knowledge graph."
        exit 0
      fi
      query_graph_json "$graph_file" "$cmd"
      ;;

    *)
      echo "FATAL: unknown command '$cmd'." >&2
      echo "Usage: graphify.sh <command> [options]" >&2
      exit 1
      ;;
  esac
}

main "$@"
