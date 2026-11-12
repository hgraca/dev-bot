#!/usr/bin/env bash
# =============================================================================
# src/agentic/autobot/update.sh
# Re-registers the cron entry so an update cannot leave a stale path behind.
# =============================================================================

set -euo pipefail

# shellcheck source=./functions.sh
source "$(dirname "${BASH_SOURCE[0]}")/functions.sh"

main() {
  _info "autobot — update"
  "$(dirname "${BASH_SOURCE[0]}")/install.sh"
}

main "$@"
