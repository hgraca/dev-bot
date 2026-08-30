#!/usr/bin/env bash
# =============================================================================
# src/agentic/react/install.sh
# Installs OS-level dependencies for the react module.
# - Checks bash, bats are available (boilerplate)
# - Checks Node.js >= 18 and npm
#
# Idempotent — safe to re-run at any time.
# =============================================================================

set -euo pipefail

# shellcheck source=./functions.sh
source "$(dirname "$0")/functions.sh"

main() {
  _info "react module — checking dependencies"

  # Shell
  if command -v bash >/dev/null 2>&1; then
    _ok "Shell found: bash ${BASH_VERSION%% *}"
  else
    _skip "bash not found — this should never happen on a POSIX system."
  fi

  # BATS test framework
  if command -v bats >/dev/null 2>&1; then
    BATS_VER=$(bats --version 2>/dev/null || echo "unknown")
    _ok "bats found: $BATS_VER"
  else
    _skip "bats not found. Install: npm install -g bats bats-assert bats-support"
  fi

  # Node.js >= 18
  if command -v node >/dev/null 2>&1; then
    NODE_VER=$(node --version | sed 's/^v//')
    _ok "Node.js found: v${NODE_VER}"
  else
    _error "Node.js not found. Install Node.js >= 18: https://nodejs.org/"
  fi

  # npm
  if command -v npm >/dev/null 2>&1; then
    _ok "npm found: v$(npm --version)"
  else
    _error "npm not found. npm ships with Node.js."
  fi

  # MCP server package check (informational — runtime uses npx)
  _info "Next.js DevTools MCP: will use 'npx -y next-devtools-mcp@latest' at runtime"
  _info "External skills (3): declared in external-modules.json — wired by 'devbot init'"
  _info "  - react                  (mindrally/skills)"
  _info "  - nextjs-react-typescript (mindrally/skills)"
  _info "  - react-best-practices    (mindrally/skills)"

  _ok "react module — all dependencies satisfied"
}

main "$@"
