#!/usr/bin/env bash
# src/agentic/datasources/install.sh
# Ensures the pinned mcp-toolbox image is present, then renders the gateway's
# runtime artifacts. Idempotent — safe to re-run.
set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "${MODULE_DIR}/../../.." && pwd)}"
export DEV_BOT_ROOT

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

# shellcheck source=./versions.env
source "${MODULE_DIR}/versions.env"

main() {
  _info "datasources — install"

  if ! command -v docker >/dev/null 2>&1; then
    _warn "docker not found — the datasources gateway needs it. Skipping."
    return 0
  fi

  local image="${TOOLBOX_IMAGE}:${TOOLBOX_VERSION}"
  local declared
  declared="$(_datasources_declared_count 2>/dev/null || true)"
  if [[ "${declared}" == "0" ]]; then
    # Nothing declared → nothing for the gateway to serve → no image needed. A
    # fresh install ships an empty catalogue, so pulling here only warned
    # (audit-80 N8). A failed count (empty output) still pulls — safe direction.
    _skip "datasources — no datasources declared; skipping the toolbox image pull"
  elif docker image inspect "${image}" >/dev/null 2>&1; then
    _skip "datasources — image ${image} already present"
  else
    _info "pulling ${image}"
    if docker pull "${image}"; then
      _ok "pulled ${image}"
    else
      # Non-fatal: the gateway is simply unavailable until the image resolves.
      _warn "could not pull ${image} — the datasources gateway will be unavailable"
    fi
  fi

  bash "${MODULE_DIR}/render.sh"
}

main "$@"
