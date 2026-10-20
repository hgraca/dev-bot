#!/usr/bin/env bash
# =============================================================================
# src/agentic/rfp/update.sh
# The rfp module has no versioned dependency to update. Re-run install.sh so a
# never-installed or repaired checkout self-heals (devbot update does not run
# install.sh).
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

main() {
  _info "rfp — update"
  bash "${MODULE_DIR}/install.sh"
  _ok "rfp update complete"
}

main "$@"
