#!/usr/bin/env bash
# =============================================================================
# src/agentic/chrome-devtools/update.sh
# Updates chrome-devtools — re-runs the install flow so a sandboxable
# Chromium is present (or re-downloaded if a version bump requires it).
#
# audit-25 F4: chrome-devtools cannot launch without a Playwright-downloaded
# Chromium; updating must ensure it exists, not just report.
#
# GATE: This module must work on Ubuntu, Fedora, and macOS.
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../../_shared/functions.sh
source "${MODULE_DIR}/../../_shared/functions.sh"

main() {
  _info "chrome-devtools — update"
  # Re-run install: idempotent, ensures chromium is present.
  bash "${MODULE_DIR}/install.sh"
  _ok "chrome-devtools update complete"
}

main "$@"
