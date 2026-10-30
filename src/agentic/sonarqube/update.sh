#!/usr/bin/env bash
# src/agentic/sonarqube/update.sh
# Bump the SonarQube MCP server image pin to the newest 1.x release after its
# manifest is verified. The image itself is pulled lazily on the next start.
# Skills update separately via the external-modules module on `devbot update`.
#
# Never fails on a registry problem: an offline machine keeps its current pin
# and image rather than losing a working install.
#
# GATE: This module must work on Ubuntu, Fedora, and macOS.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

main() {
  _info "SonarQube (update)"

  local latest=""
  if latest="$(_sonarqube_latest_tag)" && [[ -n "${latest}" ]]; then
    # Verify the candidate tag exists before committing it: a pin written for a
    # tag that cannot be fetched would strand the next launch on a dead image.
    # `manifest inspect` fetches metadata only — it never downloads the layers.
    if ! docker manifest inspect "sonarsource/sonarqube-mcp:${latest}" >/dev/null 2>&1; then
      _warn "could not verify sonarsource/sonarqube-mcp:${latest} — keeping the existing pin"
    else
      # sed->tmp->mv (no bare `sed -i` — macOS requires a backup suffix).
      sed "s/^SONARQUBE_MCP_IMAGE_TAG=.*/SONARQUBE_MCP_IMAGE_TAG=${latest}/" \
        "${MODULE_DIR}/versions.env" > "${MODULE_DIR}/versions.env.tmp" \
        && mv "${MODULE_DIR}/versions.env.tmp" "${MODULE_DIR}/versions.env"
      _ok "pin bumped to ${latest} (versions.env)"
    fi
  else
    _warn "could not resolve the latest image tag (offline?) — keeping the existing pin"
  fi

  # Re-run install: verifies docker is present. It never pulls — the launcher
  # does that lazily on first use.
  bash "${MODULE_DIR}/install.sh"

  _ok "SonarQube update complete"
}

main "$@"
