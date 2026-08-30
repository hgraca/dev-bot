#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/functions.sh"

main() {
  _info "tools-mcp"

  if ! command -v bun >/dev/null 2>&1; then
    _info "Installing bun (tools-mcp server runtime)..."
    if ! command -v curl >/dev/null 2>&1; then
      _warn "curl is required to install bun — install curl first"
      exit 1
    fi
    # The bun installer needs unzip to extract the binary.
    if ! command -v unzip >/dev/null 2>&1; then
      _info "Installing unzip (bun installer dependency)..."
      if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get install -y unzip >/dev/null 2>&1 || { _warn "could not install unzip"; exit 1; }
      elif command -v brew >/dev/null 2>&1; then
        brew install unzip >/dev/null 2>&1 || { _warn "could not install unzip"; exit 1; }
      fi
    fi
    if ! curl -fsSL https://bun.sh/install | bash >/dev/null 2>&1; then
      _warn "bun install failed — tools-mcp server unavailable"
      exit 1
    fi
    # The installer drops bun at ~/.bun/bin — link it onto the devbot PATH
    # (~/.local/bin) so the server and this check can find it.
    if [[ -x "$HOME/.bun/bin/bun" ]]; then
      mkdir -p "$HOME/.local/bin"
      ln -sf "$HOME/.bun/bin/bun" "$HOME/.local/bin/bun"
    fi
  fi

  _ok "tools-mcp (bun $(bun --version))"
}

main
