#!/usr/bin/env bash
# =============================================================================
# src/agentic/argocd/pre.sh
# Prerequisites check for the argocd module.
#
# Run by bin/install.sh and bin/update.sh — looped over all agentic modules.
# The module's install.sh provisions only the argocd CLI; kubectl/jq/curl are
# user-provided runtime needs, so their absence warns instead of failing a
# machine-wide install.
#
# GATE: This module must work on Ubuntu, Fedora, and macOS.
# =============================================================================

set -euo pipefail

# shellcheck source=./functions.sh
source "$(dirname "${BASH_SOURCE[0]}")/functions.sh"

main() {
  _info "argocd — prerequisites"

  export PATH="${ARGOCD_BIN_DIR:-$HOME/.local/bin}:$PATH"

  _prereq_module_installed argocd "argocd CLI"

  for bin in kubectl curl jq openssl; do
    if command -v "$bin" >/dev/null 2>&1; then
      _ok "$bin"
    else
      _warn "$bin not found — required at runtime by the argocd scripts"
    fi
  done

  return 0
}

main "$@"
