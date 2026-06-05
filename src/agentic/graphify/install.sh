#!/usr/bin/env bash
# Install graphify (codebase knowledge graph tool) via uv.
# Installs the graphify CLI, stores the Python interpreter path for MCP,
# and registers MCP servers for both OpenCode and Claude Code.
#
# GATE: This module must work on Ubuntu, Fedora, and macOS.

set -euo pipefail

# shellcheck source=./functions.sh
source "$(dirname "$0")/functions.sh"

main() {
  _info "graphify"

  # ── Dependency check: uv ──────────────────────────────────────────────────
  if ! command -v uv &>/dev/null; then
    if command -v curl &>/dev/null; then
      _info "Installing uv (Python package manager)..."
      curl -LsSf https://astral.sh/uv/install.sh | sh 2>/dev/null || {
        _error "uv installation failed. Install manually: curl -LsSf https://astral.sh/uv/install.sh | sh"
        exit 1
      }
      export PATH="$HOME/.local/bin:$PATH"
    elif command -v brew &>/dev/null; then
      _info "Installing uv via Homebrew..."
      brew install uv 2>/dev/null || {
        _error "uv installation failed."
        exit 1
      }
    else
      _error "uv is required but not installed."
      echo "  Install via: curl -LsSf https://astral.sh/uv/install.sh | sh" >&2
      exit 1
    fi
  fi

  # ── Install/verify graphify ───────────────────────────────────────────────
  local needs_install=false
  if ! command -v graphify &>/dev/null; then
    needs_install=true
  elif ! uv tool run --from graphifyy python3 -c 'import graphify.serve' 2>/dev/null; then
    _warn "graphify CLI found but Python module not importable — reinstalling"
    needs_install=true
  fi

  if $needs_install; then
    _info "Installing graphifyy via uv..."
    uv tool install graphifyy --with mcp 2>&1 | sed 's/^/  /'
    export PATH="$HOME/.local/bin:$PATH"
    _ok "Graphify installed: $(graphify --version 2>/dev/null || true)"
  else
    _skip "Graphify ($(graphify --version 2>/dev/null || echo 'installed'))"
  fi

  # ── Store Python interpreter path for MCP server ──────────────────────────
  # The MCP server (start-graphify-mcp.sh) reads this path to exec
  # graphify.serve with the correct Python interpreter, avoiding the latency
  # of resolving via `uv tool run` on every MCP launch.
  local secrets_dir="${DEV_BOT_ROOT}/storage/secrets"
  mkdir -p "${secrets_dir}"

  if GRAPHIFY_PYTHON="$(uv tool run --from graphifyy python3 -c 'import sys; print(sys.executable)' 2>/dev/null)"; then
    printf '%s' "${GRAPHIFY_PYTHON}" > "${secrets_dir}/graphify-python"
    _skip "Stored graphify Python: ${GRAPHIFY_PYTHON}"
  else
    _skip "Could not resolve graphify Python path — MCP server will fall back to system python3"
  fi

  # ── Register MCP server for Claude Code ────────────────────────────────────
  # The mcp-server.js proxy handles both stub and proxy modes.
  # Registration in .mcp.json is manual (per-project).
  _skip "Claude Code MCP: register in .mcp.json:"
  _skip "  { \"mcpServers\": { \"graphify\": { \"command\": \"node\", \"args\": [\"src/agentic/graphify/tools/claudecode/mcp-server.js\"] } } }"
  _skip "OpenCode tool: available via tools/opencode/graphify.ts (register in opencode.jsonc)"
  _skip "No OS-level dependencies to install"
}

main
