#!/usr/bin/env bash
# src/agentic/sentry/install.sh
# Install the Sentry agent skills.
#
# The MCP server itself is not installed per machine: Sentry hosts it at
# https://mcp.sentry.dev/mcp (see mcp.json), so the harness connects over http
# carrying the SENTRY_ACCESS_TOKEN header. Only the agent skills are fetched.
#
# Idempotent — skips when the skills are already installed.
#
# GATE: Requires npx.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

SKILLS_DIR="$(_sentry_storage_dir)/skills"

# ── Main ───────────────────────────────────────────────────────────────────────

main() {
  echo
  _info "Sentry (error-monitoring MCP server + agent skills)"

  # ── Skills ───────────────────────────────────────────────────────────────────
  if [[ -d "${SKILLS_DIR}" ]] && [[ -n "$(ls -A "${SKILLS_DIR}" 2>/dev/null)" ]]; then
    _skip "Sentry agent skills already installed (${SKILLS_DIR}/)"
  else
    _sentry_install_skills || true
  fi

  _log "Sentry MCP server is hosted — wired from mcp.json, nothing local to start"
}

main
