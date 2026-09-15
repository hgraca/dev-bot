#!/usr/bin/env bash
# src/agentic/signoz/install.sh
# Install SigNoz agent skills.
#
# The MCP server itself is not downloaded per machine: it runs as a shared
# machine-wide container from the official image (see docker-compose.yml), so
# there is no binary to fetch or symlink into each harness dir. The image is
# pulled by `devbot up`.
#
# Idempotent — skips when the skills are already installed.
#
# GATE: Requires npx.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

STORAGE_DIR="$(_signoz_storage_dir)"
SKILLS_DIR="${STORAGE_DIR}/skills"

# ── Main ───────────────────────────────────────────────────────────────────────

main() {
  echo
  _info "SigNoz (observability MCP server + agent skills)"

  # ── Skills ───────────────────────────────────────────────────────────────────
  if [[ -d "${SKILLS_DIR}" ]] && [[ -n "$(ls -A "${SKILLS_DIR}" 2>/dev/null)" ]]; then
    _skip "SigNoz agent skills already installed (${SKILLS_DIR}/)"
  else
    _signoz_install_skills || true
  fi

  _log "SigNoz MCP server runs as a shared container — started by 'devbot up'"
}

main
