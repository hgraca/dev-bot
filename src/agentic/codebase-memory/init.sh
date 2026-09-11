#!/usr/bin/env bash
# =============================================================================
# src/agentic/codebase-memory/init.sh
# Dependency self-heal for the codebase-memory module.
#
# The MCP server is registered in the harness config from the canonical
# mcp.json, and install.sh installs the `codebase-memory-mcp` binary. But
# `devbot update` runs only update.sh (which self-heals), while
# `devbot init`/`reinit` run only init.sh — so a reinit WITHOUT a preceding
# update can leave the MCP server registered with no binary, failing with
#   "exec: codebase-memory-mcp: not found"
# in .agents/logs/codebase-memory-mcp.log. This init closes that gap by
# delegating to the module's own idempotent install.sh whenever the binary is
# absent, so `devbot reinit` self-heals the dependency.
#
# Writes no per-project config — codebase-memory-mcp stores settings
# account-wide via `config set`.
#
# Idempotent — safe to re-run.
#
# Usage:
#   init.sh                    # invoked by bin/init.sh
#
# The project directory bin/init.sh forwards as $1 is intentionally ignored —
# this module has no per-project state to set up.
#
# GATE: Must work on Ubuntu, Fedora, and macOS.
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

# ── main ─────────────────────────────────────────────────────────────────────

main() {
  if command -v codebase-memory-mcp >/dev/null 2>&1; then
    _skip "codebase-memory-mcp already installed"
    return 0
  fi

  _warn "codebase-memory-mcp not found — running install.sh"
  bash "${MODULE_DIR}/install.sh"
}

main
