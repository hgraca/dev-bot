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

  "${MODULE_DIR}/scripts/tooling.sh" install
  _ok "security tooling up to date"
}

main "$@"
