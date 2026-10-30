#!/usr/bin/env bash
# src/agentic/sonarqube/install.sh
# Verify the SonarQube MCP prerequisites without downloading anything.
#
# Install must stay cheap (`bin/install.sh` runs every module's install.sh, so an
# eager image download would fetch an image for a module the machine may never
# enable). The pinned image is pulled lazily by the launcher on the first start
# that needs it; the official agent skills are cloned and wired by the
# external-modules module.
#
# Idempotent — safe to re-run.
#
# GATE: This module must work on Ubuntu, Fedora, and macOS.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

main() {
  _info "SonarQube (MCP server + agent skills)"

  if ! command -v docker >/dev/null 2>&1; then
    _fatal "docker is required but not installed — the SonarQube MCP server runs as a container."
    exit 1
  fi
  _ok "docker ($(docker --version 2>/dev/null || echo 'found'))"

  local image
  image="$(_sonarqube_image)"
  _info "${image} is pulled on the first MCP start (not at install time)"
  _info "SonarQube agent skills install via external-modules (devbot install/init)"
}

main
