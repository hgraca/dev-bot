#!/usr/bin/env bash
# =============================================================================
# src/harnesses/opencode-v2/up.sh
# Pre-launch check for the opencode-v2 harness: refuses an opencode 1.x host.
#
# This module's hooks and TUI parts use the opencode V2 plugin API, which 1.x
# does not have — on a 1.x host none of them load. Runs on `devbot`,
# `devbot up` and `make up` (auto-discovered by bin/up.sh).
#
# A non-zero exit here is REPORTED but not fatal to the start sequence:
# _run_service_scripts warns about a failed module script and still returns 0.
# start.sh re-runs the same check, and only there is the launch refused.
#
# Usage:
#   up.sh [project_dir]
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

# The unselected harness is disabled, so _run_service_scripts skips this here.
# The guard below only covers a direct invocation.
if [[ "$(_devbot_get_harness "${1:-.}")" != "opencode-v2" ]]; then
  exit 0
fi

if ! _devbot_require_opencode_2x; then
  exit 1
fi
