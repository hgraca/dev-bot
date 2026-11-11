#!/usr/bin/env bash
# =============================================================================
# src/harnesses/opencode/up.sh
# Pre-launch check for the opencode harness: refuses an opencode 2.x host.
#
# dev-bot's hooks and TUI plugins use the opencode V1 plugin API, which v2
# replaced — on a v2 host none of them load. Runs on `devbot`, `devbot up` and
# `make up` (auto-discovered by bin/up.sh).
#
# A non-zero exit here is REPORTED but not fatal to the start sequence:
# _run_service_scripts warns about a failed module script and still
# returns 0. start.sh re-runs the same check, and only there is the launch
# actually refused.
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
if [[ "$(_devbot_get_harness "${1:-.}")" != "opencode" ]]; then
  exit 0
fi

if ! _devbot_require_opencode_1x; then
  exit 1
fi
