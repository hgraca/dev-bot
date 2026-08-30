#!/usr/bin/env bash
# =============================================================================
# src/agentic/graphify/tools/start-graphify-mcp.sh
# MCP server proxy for graphify.serve (Python MCP server).
# Symlinked as .opencode/graphify-serve.sh in each project.
#
# Finds the Python interpreter with graphify.serve installed, then execs it.
# The graph.json path is passed as $1 (from the MCP config).
#
# If graph.json doesn't exist yet, this blocks (up to GRAPHIFY_MCP_WAIT_SECONDS,
# default 120) for the background graph build to finish. Exiting here would make
# opencode mark the local MCP server "failed" permanently (it does not hot-restart).
# =============================================================================
set -euo pipefail

GRAPH_FILE="${1:?Usage: $(basename "$0") <path-to-graph.json>}"

# ── Resolve DEVBOT_ROOT from this script's real location ─────────────────────
# This script is symlinked as .opencode/graphify-serve.sh in each project, so
# DEVBOT_ROOT is not exported in the MCP runtime. Resolve the symlink target so
# storage/secrets/graphify-python is found.
if [[ -z "${DEVBOT_ROOT:-}" ]]; then
  SOURCE="${BASH_SOURCE[0]}"
  while [[ -L "${SOURCE}" ]]; do
    DIR="$(cd -P "$(dirname "${SOURCE}")" && pwd)"
    SOURCE="$(readlink "${SOURCE}")"
    [[ "${SOURCE}" != /* ]] && SOURCE="${DIR}/${SOURCE}"
  done
  DEVBOT_ROOT="$(cd -P "$(dirname "${SOURCE}")/../../../.." && pwd)"
fi

# shellcheck source=/dev/null
source "${DEVBOT_ROOT}/src/_shared/functions.sh"

# ── EPIPE-swallowing shim ─────────────────────────────────────────────────────
# `python -m graphify.serve` crashes with an unhandled BrokenPipeError (logged
# as a scary traceback) every time the MCP client closes the stdio pipe at
# session teardown. All exec sites below route through graphify-serve-shim.py,
# which runs the same module but exits cleanly on that teardown EPIPE (audit-18
# NOTE: rotated/*graphify-mcp-*.log crash traces).
GRAPHIFY_SHIM="${DEVBOT_ROOT}/src/agentic/graphify/tools/graphify-serve-shim.py"

# ── Wait for graph.json ──────────────────────────────────────────────────────
# On first init the graph is built in the background (nohup graphify update)
# and can take ~1 min. If opencode launches this MCP server before the build
# finishes, block until graph.json appears (or give up after the timeout).
if [[ ! -f "${GRAPH_FILE}" ]]; then
  WAIT_SECONDS="${GRAPHIFY_MCP_WAIT_SECONDS:-120}"
  waited=0
  while [[ ! -f "${GRAPH_FILE}" && ${waited} -lt ${WAIT_SECONDS} ]]; do
    sleep 1
    waited=$((waited + 1))
  done
  if [[ ! -f "${GRAPH_FILE}" ]]; then
    _log_file ".agents/logs/graphify-mcp.log" "graphify: graph.json still absent at ${GRAPH_FILE} after ${WAIT_SECONDS}s — giving up"
    exit 0
  fi
fi

# Try the interpreter recorded by install.sh (stores Python path with graphify.serve)
if [[ -f "${DEVBOT_ROOT}/storage/secrets/graphify-python" ]]; then
  PYTHON="$(cat "${DEVBOT_ROOT}/storage/secrets/graphify-python")"
  if command -v "${PYTHON}" >/dev/null 2>&1; then
    exec "${PYTHON}" "${GRAPHIFY_SHIM}" "${GRAPH_FILE}"
  fi
fi

# Fallback: try uv-managed graphifyy installation
if command -v uv >/dev/null 2>&1; then
  PYTHON="$(uv tool run --from graphifyy python3 -c 'import sys; print(sys.executable)' 2>/dev/null)" || true
  if [[ -n "${PYTHON:-}" ]] && command -v "${PYTHON}" >/dev/null 2>&1; then
    exec "${PYTHON}" "${GRAPHIFY_SHIM}" "${GRAPH_FILE}"
  fi
fi

# Auto-detect: find a Python with graphify.serve available
for py in python3 python; do
  if command -v "${py}" >/dev/null 2>&1 && "${py}" -c "import graphify.serve" 2>/dev/null; then
    exec "${py}" "${GRAPHIFY_SHIM}" "${GRAPH_FILE}"
  fi
done

_log_file ".agents/logs/graphify-mcp.log" "graphify: could not find Python with graphify.serve module"
exit 1
