#!/usr/bin/env bash
# src/agentic/sonarqube/functions.sh
# Shared helpers for the SonarQube module scripts (install.sh, update.sh).

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_shared/functions.sh
source "${MODULE_DIR}/../../_shared/functions.sh"

# The official SonarQube MCP server image. versions.env pins the tag; a machine
# can override the whole image (e.g. a tag aligned to its SonarQube Server
# version) with SONARQUBE_MCP_IMAGE.
_sonarqube_image() {
  local tag=""
  # shellcheck source=./versions.env
  [[ -f "${MODULE_DIR}/versions.env" ]] && source "${MODULE_DIR}/versions.env"
  tag="${SONARQUBE_MCP_IMAGE_TAG:-latest}"
  printf '%s' "${SONARQUBE_MCP_IMAGE:-sonarsource/sonarqube-mcp:${tag}}"
}

# Newest release on the generic 1.x line. The 2026.x tags are Server-aligned
# aliases of the same releases, so following them would flip the pin between
# two version schemes on every update.
_sonarqube_latest_tag() {
  command -v curl >/dev/null 2>&1 || return 1
  curl -fsSL \
    "https://hub.docker.com/v2/repositories/sonarsource/sonarqube-mcp/tags?page_size=100&ordering=last_updated" \
    2>/dev/null |
    python3 -c '
import json, re, sys
try:
    tags = [r["name"] for r in json.load(sys.stdin).get("results", [])]
except Exception:
    sys.exit(1)
versions = [t for t in tags if re.fullmatch(r"1\.\d+\.\d+\.\d+", t)]
if not versions:
    sys.exit(1)
print(max(versions, key=lambda t: tuple(int(p) for p in t.split("."))))
'
}
