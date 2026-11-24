#!/usr/bin/env bash
# =============================================================================
# src/agentic/security/update.sh
# Re-provisions the security module's FOSS tooling to current releases.
#
# GATE: Linux and macOS. `check` needs no network; `install` reaches the Go
# module proxy, PyPI and the container registry.
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

main() {
  _info "security — update tooling"

  if [ ! -x "${MODULE_DIR}/scripts/tooling.sh" ]; then
    _warn "scripts/tooling.sh missing or not executable — nothing to update"
    return 0
  fi

  # Force a re-fetch: without it the idempotent install reports every present
  # tool as "already installed" and `devbot update` updates nothing. A failed
  # refresh must not report success — the module runner reads the exit status.
  if SEC_TOOLS_FORCE=1 "${MODULE_DIR}/scripts/tooling.sh" install; then
    _ok "security tooling update pass complete"
  else
    _warn "some tooling could not be updated — see the ledger above"
    return 1
  fi
}

main "$@"
