#!/usr/bin/env bash
# =============================================================================
# src/agentic/svelte/install.sh
# Installs OS-level dependencies for the svelte module.
# - Checks bash, bats are available (boilerplate)
# - Checks Node.js >= 18 and npm (delegates to pre.sh on first run)
#
# Idempotent — safe to re-run at any time.
# =============================================================================

set -euo pipefail

# shellcheck source=./functions.sh
source "$(dirname "$0")/functions.sh"

# Info/ok/skip helpers
info()  { printf "  [ \033[33mINFO\033[0m ] %s\n" "$*"; }
ok()    { printf "  [  \033[32mOK\033[0m  ] %s\n" "$*"; }
skip()  { printf "  [ \033[36mSKIP\033[0m ] %s\n" "$*"; }

main() {
  info "svelte module — checking dependencies"

  # Shell
  if command -v bash >/dev/null 2>&1; then
    ok "Shell found: bash ${BASH_VERSION%% *}"
  else
    skip "bash not found — this should never happen on a POSIX system."
  fi

  # BATS test framework
  if command -v bats >/dev/null 2>&1; then
    BATS_VER=$(bats --version 2>/dev/null || echo "unknown")
    ok "bats found: $BATS_VER"
  else
    skip "bats not found. Install: npm install -g bats bats-assert bats-support"
  fi

  # Node.js >= 18
  if command -v node >/dev/null 2>&1; then
    NODE_VER=$(node --version | sed 's/^v//')
    ok "Node.js found: v${NODE_VER}"
  else
    _error "Node.js not found. Install Node.js >= 18: https://nodejs.org/"
  fi

  # npm
  if command -v npm >/dev/null 2>&1; then
    ok "npm found: v$(npm --version)"
  else
    _error "npm not found. npm ships with Node.js."
  fi

  # MCP server package check (informational — runtime uses npx)
  info "Svelte MCP server: will use 'npx -y @sveltejs/mcp' at runtime"
  info "External skills (3): declared in external-modules.json — wired by 'devbot init'"
  info "  - svelte                (mindrally/skills)"
  info "  - sveltekit-structure   (spences10/svelte-skills-kit)"
  info "  - svelte5-best-practices (ejirocodes/agent-skills)"

  ok "svelte module — all dependencies satisfied"
}

main "$@"
