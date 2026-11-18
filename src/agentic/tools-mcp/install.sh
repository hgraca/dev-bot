#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/functions.sh"

main() {
  _info "tools-mcp"

  if ! _devbot_ensure_bun; then
    _warn "tools-mcp server unavailable — bun could not be installed"
    exit 1
  fi

  _ok "tools-mcp (bun $(bun --version))"
}

main
