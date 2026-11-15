#!/usr/bin/env bash
set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${1:-$(pwd)}" && pwd)"

source "${MODULE_DIR}/functions.sh"

# Force-correct DEV_BOT_ROOT — _shared/functions.sh computes it one level too deep
# shellcheck disable=SC2034  # consumed by the sourced _shared functions
DEV_BOT_ROOT="$(cd "${MODULE_DIR}/../../.." && pwd)"

_header_3 "Tools MCP Init"

PROJECT_NAME="$(basename "${PROJECT_DIR}")"

# ── Check if harnesses are disabled ──────────────────────────────────────────

  # The harness links this module's declared MCP assets (mcp.json "assets").
_log "Tools MCP init complete for ${PROJECT_NAME}"
