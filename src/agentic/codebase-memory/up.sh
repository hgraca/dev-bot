#!/usr/bin/env bash
# =============================================================================
# src/agentic/codebase-memory/up.sh
# Brings the shared codebase-memory MCP gateway (the docker compose service
# declared in this module's docker-compose.yml) to the desired state, then waits
# for it to accept MCP requests, so the harness that starts right after
# `devbot up` finds it ready.
#
# Runs on `devbot up` — after docker services are started. The project directory
# is passed as $1 by bin/up.sh; falls back to cwd (unused here).
#
# Non-fatal: if the gateway never comes up, warn and continue — the harness
# starts with the codebase-memory MCP server unavailable rather than failing the
# boot.
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

CODEBASE_MEMORY_MCP_URL="${CODEBASE_MEMORY_MCP_URL:-http://127.0.0.1:18504/mcp}"
CONTAINER_NAME="dev-bot-codebase-memory-mcp"
SERVICE_NAME="codebase-memory-mcp"

# ── Reconcile the repo mount against the desired root ──────────────────────────
# Docker fixes a bind mount at container CREATION, and bin/up.sh runs compose
# with --no-recreate, so exporting a different CODEBASE_MEMORY_ROOT had no
# effect until the container was recreated. The old workaround (`devbot down &&
# devbot up`) no longer works from inside a session — down is gated on the
# session registry and keeps the containers while any instance is alive. So
# detect the drift and force-recreate here, the shape of bin/up.sh's
# _reconcile_ollama_gpu.
_reconcile_repo_mount() {
  local cid
  cid="$(docker ps -aq --filter "name=^${CONTAINER_NAME}$" 2>/dev/null | head -1 || true)"
  # Not created yet: the compose call in bin/up.sh already used the right root.
  [[ -z "${cid}" ]] && return 0

  # The one bind mount on the container is the repo root (the store is a named
  # volume, so it is not type=bind).
  local actual
  actual="$(docker inspect "${cid}" \
    --format '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}}{{"\n"}}{{end}}{{end}}' \
    2>/dev/null | head -1 || true)"
  [[ -z "${actual}" ]] && return 0

  local desired="${CODEBASE_MEMORY_ROOT:-${HOME}}"
  [[ "${actual}" == "${desired}" ]] && return 0

  _warn "codebase-memory — repo mounted at '${actual}', desired '${desired}' — recreating the gateway"
  if docker compose -f "${MODULE_DIR}/docker-compose.yml" \
    up -d --force-recreate "${SERVICE_NAME}"; then
    _ok "codebase-memory — gateway recreated with the repo at ${desired}"
  else
    _warn "codebase-memory — could not recreate the gateway with the new repo root"
  fi
}

main() {
  _info "codebase-memory — up"

  _reconcile_repo_mount

  # An `if`, not `&&`: under `set -e` a short-circuited `&&` would abort here.
  if _devbot_wait_for_mcp_gateway codebase-memory "${CODEBASE_MEMORY_MCP_URL}"; then
    _ok "codebase-memory gateway reachable at ${CODEBASE_MEMORY_MCP_URL}"
  fi

  return 0
}

main "$@"
