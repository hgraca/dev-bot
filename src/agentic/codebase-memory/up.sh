#!/usr/bin/env bash
# =============================================================================
# src/agentic/codebase-memory/up.sh
# Brings the shared codebase-memory MCP gateway (the docker compose service
# declared in this module's docker-compose.yml) to the desired state, waits for
# it to accept MCP requests, then primes the project's codebase index — so the
# harness that starts right after `devbot up` finds both ready.
#
# Waits and heals: a container that has exited is recreated once rather than
# waited on — see _heal_dead_gateway.
#
# Runs on `devbot up` — after docker services are started. The project directory
# is passed as $1 by bin/up.sh; falls back to cwd.
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

# Set once this run has attempted a force-recreate, so the shared gateway is
# recreated at most once per `devbot up`.
_GATEWAY_RECREATED=0

# Project directory, passed as $1 by bin/up.sh; falls back to cwd.
PROJECT_DIR="$(cd "${1:-$(pwd)}" 2>/dev/null && pwd || true)"

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

  local desired
  desired="$(_devbot_codebase_memory_root)"
  [[ "${actual}" == "${desired}" ]] && return 0

  _warn "codebase-memory — repo mounted at '${actual}', desired '${desired}' — recreating the gateway"
  _GATEWAY_RECREATED=1
  if docker compose -f "${MODULE_DIR}/docker-compose.yml" \
    up -d --force-recreate "${SERVICE_NAME}"; then
    _ok "codebase-memory — gateway recreated with the repo at ${desired}"
  else
    _warn "codebase-memory — could not recreate the gateway with the new repo root"
  fi
}

# ── Heal a gateway container that will not stay up ────────────────────────────
# bin/up.sh runs compose with --no-recreate, so a container whose own state went
# bad is started again and again instead of rebuilt: the server exits 1 within
# seconds ("CBM daemon could not start within 30000 ms") and nothing ever listens
# on the port. Recreating it is the only recovery — `devbot down` keeps the
# containers while any instance is alive. Skipped while the container runs, so a
# slow boot is never thrown away, and acts only on a definite reading: an inspect
# that fails says nothing about the container.
_heal_dead_gateway() {
  local cid running
  # One recreate per run: the repo-mount reconciliation may already have done it,
  # and its result still has to be checked below.
  if [[ ${_GATEWAY_RECREATED} -eq 1 ]]; then
    _warn "codebase-memory — gateway already recreated this run — not recreating it again"
    return 0
  fi

  cid="$(docker ps -aq --filter "name=^${CONTAINER_NAME}$" 2>/dev/null | head -1 || true)"
  [[ -z "${cid}" ]] && return 1

  running="$(docker inspect "${cid}" --format '{{.State.Running}}' 2>/dev/null || true)"
  [[ "${running}" == "false" ]] || return 1

  _warn "codebase-memory — gateway container is not running — recreating it"
  _GATEWAY_RECREATED=1
  if docker compose -f "${MODULE_DIR}/docker-compose.yml" \
    up -d --force-recreate "${SERVICE_NAME}"; then
    return 0
  fi
  _warn "codebase-memory — could not recreate the gateway container"
  return 1
}

# ── Prime the project's codebase index ─────────────────────────────────────────
# The engine indexes nothing on its own (auto_index=false), so the graph must be
# primed before the harness starts. index-project.sh carries every guard (active
# provider, gateway reachability, src|app resolution, mount scope) and launches
# the index detached, so this returns at once and never fails the boot.
_prime_index() {
  local script="${MODULE_DIR}/tools/index-project.sh"
  [[ -n "${PROJECT_DIR}" && -f "${script}" ]] || return 0
  bash "${script}" "${PROJECT_DIR}" || true
}

main() {
  _info "codebase-memory — up"

  _reconcile_repo_mount

  local healthy=0

  # An `if`, not `&&`: under `set -e` a short-circuited `&&` would abort here.
  if _devbot_wait_for_mcp_gateway codebase-memory "${CODEBASE_MEMORY_MCP_URL}" "" "${CONTAINER_NAME}"; then
    healthy=1
  elif _heal_dead_gateway; then
    # Naming the container fails fast on an exited one.
    # One recreate, never a retry loop.
    if _devbot_wait_for_mcp_gateway codebase-memory "${CODEBASE_MEMORY_MCP_URL}" "" "${CONTAINER_NAME}"; then
      healthy=1
    else
      _warn "codebase-memory — gateway still down after recreating its container — check the devbot-codebase-memory-store volume"
    fi
  fi

  if [[ ${healthy} -eq 1 ]]; then
    _ok "codebase-memory gateway reachable at ${CODEBASE_MEMORY_MCP_URL}"
  fi

  # Deliberately not gated on the wait above: that helper needs curl, whereas
  # index-project.sh probes the gateway itself (bash /dev/tcp) and is the real
  # authority on reachability.
  _prime_index

  return 0
}

main "$@"
