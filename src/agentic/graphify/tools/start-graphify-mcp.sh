#!/usr/bin/env bash
# =============================================================================
# src/agentic/graphify/tools/start-graphify-mcp.sh
# MCP server proxy for graphify.serve (Python MCP server).
# Symlinked as .opencode/graphify-serve.sh in each project.
#
# Finds the Python interpreter with graphify.serve installed, then execs it.
# The graph.json path is passed as $1 (from the MCP config).
#
# If graph.json doesn't exist yet, exits silently — the MCP server is
# not needed until the graph is built.
# =============================================================================
set -euo pipefail

GRAPH_FILE="${1:?Usage: $(basename "$0") <path-to-graph.json>}"

if [[ ! -f "${GRAPH_FILE}" ]]; then
  echo "graphify: no graph.json found at ${GRAPH_FILE} — skipping" >&2
  exit 0
fi

# Try the interpreter recorded by install.sh (stores Python path with graphify.serve)
if [[ -f "${DEVBOT_ROOT:-}/storage/secrets/graphify-python" ]]; then
  PYTHON="$(cat "${DEVBOT_ROOT}/storage/secrets/graphify-python")"
  if command -v "${PYTHON}" &>/dev/null; then
    exec "${PYTHON}" -m graphify.serve "${GRAPH_FILE}"
  fi
fi

# Fallback: try uv-managed graphifyy installation
if command -v uv &>/dev/null; then
  PYTHON="$(uv tool run --from graphifyy python3 -c 'import sys; print(sys.executable)' 2>/dev/null)" || true
  if [[ -n "${PYTHON:-}" ]] && command -v "${PYTHON}" &>/dev/null; then
    exec "${PYTHON}" -m graphify.serve "${GRAPH_FILE}"
  fi
fi

# Auto-detect: find a Python with graphify.serve available
for py in python3 python; do
  if command -v "${py}" &>/dev/null && "${py}" -c "import graphify.serve" 2>/dev/null; then
    exec "${py}" -m graphify.serve "${GRAPH_FILE}"
  fi
done

echo "graphify: could not find Python with graphify.serve module" >&2
exit 1
