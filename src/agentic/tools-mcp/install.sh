#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/functions.sh"

main() {
  _info "tools-mcp"

  if ! command -v bun &>/dev/null; then
    _warn "bun is required to run the tools-mcp server"
    _warn "Install: curl -fsSL https://bun.sh/install | bash"
    exit 1
  fi

  _ok "tools-mcp (bun $(bun --version))"
}

main
