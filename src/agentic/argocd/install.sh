#!/usr/bin/env bash
# Install the argocd CLI — idempotent, skips when already present.

set -euo pipefail

# shellcheck source=./functions.sh
source "$(dirname "${BASH_SOURCE[0]}")/functions.sh"

main() {
  _info "argocd"

  export PATH="${ARGOCD_BIN_DIR:-$HOME/.local/bin}:$PATH"

  if command -v argocd >/dev/null 2>&1; then
    _skip "argocd $(argocd version --client --short 2>/dev/null || echo installed)"
    return 0
  fi

  _info "installing the argocd CLI..."
  if bash "${MODULE_DIR}/scripts/argocd-install.sh"; then
    _ok "argocd $(command -v argocd >/dev/null 2>&1 && argocd version --client --short 2>/dev/null || echo installed)"
  else
    _error "argocd install failed — run scripts/argocd-install.sh manually"
    return 1
  fi
}

main "$@"
