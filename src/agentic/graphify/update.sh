#!/usr/bin/env bash
# Update graphify (codebase knowledge graph tool) via uv.
# Upgrades graphifyy and restores the --with mcp dependency.
#
# GATE: This module must work on Ubuntu, Fedora, and macOS.

set -euo pipefail

# shellcheck source=./functions.sh
source "$(dirname "$0")/functions.sh"

main() {
  _info "graphify"

  if ! command -v graphify &>/dev/null; then
    _skip "Graphify not installed — run bin/install.sh first."
    exit 0
  fi

  local before
  before="$(graphify --version 2>/dev/null || echo 'unknown')"

  _info "Upgrading graphifyy via uv..."
  if uv tool upgrade graphifyy 2>/dev/null; then
    # Restore --with mcp dependency (uv tool upgrade strips extras)
    uv tool install graphifyy --with mcp --force 2>/dev/null || true

    local after
    after="$(graphify --version 2>/dev/null || echo 'unknown')"

    # Re-store Python interpreter path for MCP server
    local secrets_dir="${DEV_BOT_ROOT}/storage/secrets"
    mkdir -p "${secrets_dir}"
    if GRAPHIFY_PYTHON="$(uv tool run --from graphifyy python3 -c 'import sys; print(sys.executable)' 2>/dev/null)"; then
      printf '%s' "${GRAPHIFY_PYTHON}" > "${secrets_dir}/graphify-python"
    fi

    if [[ "$before" == "$after" ]]; then
      _ok "Graphify already up to date (${before})"
    else
      _ok "Graphify upgraded: ${before} → ${after}"
    fi
  else
    _error "Graphify upgrade failed — try: uv tool upgrade graphifyy"
    exit 1
  fi
}

main
