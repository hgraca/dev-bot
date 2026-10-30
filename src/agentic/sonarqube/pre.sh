#!/usr/bin/env bash
# src/agentic/sonarqube/pre.sh
# Prerequisites check for the SonarQube module.
# Run automatically by bin/install.sh and bin/update.sh.
#
# Classification (see the PDR on prerequisite reporting):
#   - docker: manual, fatal — the MCP server runs as a container.
#   - SONARQUBE_TOKEN: advisory — the server starts only when the MCP is
#     enabled, and cannot authenticate without it.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

_main() {
  _header_3 "SonarQube prerequisites"

  _prereq_manual docker "docker (for the SonarQube MCP server container)"

  if [[ -n "${SONARQUBE_TOKEN:-}" ]]; then
    _ok "SONARQUBE_TOKEN is set"
  else
    _notice "SONARQUBE_TOKEN is unset — the MCP server cannot authenticate until it is exported"
  fi

  if [[ -n "${SONARQUBE_URL:-}" ]]; then
    _ok "SONARQUBE_URL is set (SonarQube Server or Cloud US)"
  else
    _info "SONARQUBE_URL is unset — SonarQube Cloud (https://sonarcloud.io) is assumed"
  fi

  if [[ -n "${SONARQUBE_ORG:-}" ]]; then
    _ok "SONARQUBE_ORG=${SONARQUBE_ORG} (Cloud organization)"
  fi
}

_main
