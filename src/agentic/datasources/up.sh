#!/usr/bin/env bash
# src/agentic/datasources/up.sh
# Brings the datasource gateway up: re-renders the artifacts, then starts the
# module-generated compose file.
#
# The compose file is rendered into storage/datasources/ rather than shipped in
# the module dir because the gateway must receive the env var names declared in
# .devbot.global.jsonc, and those names are dynamic. bin/up.sh discovers compose
# files by scanning src/{tools,agentic,harnesses}, so it does not see this one —
# the module brings its own compose up (and down.sh takes it back down).
#
# Non-fatal by design: a gateway that will not start must not fail the boot.
set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "${MODULE_DIR}/../../.." && pwd)}"
export DEV_BOT_ROOT

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

# shellcheck source=./versions.env
source "${MODULE_DIR}/versions.env"

RUNTIME_DIR="${DEV_BOT_ROOT}/storage/datasources"
COMPOSE_FILE="${RUNTIME_DIR}/docker-compose.yml"
POLLER_PID="${RUNTIME_DIR}/refresh.pid"
MCP_URL="http://127.0.0.1:${DATASOURCES_PORT:-18510}/mcp"

# Keep the running gateway in step with what is reachable. This is what lets a
# database that comes up AFTER `devbot up` activate without a restart — the
# usual case, since the dev environment is often booted later than devbot.
_start_poller() {
  # Restart any existing poller rather than leaving it. It snapshots the
  # environment at start, and this run may have just loaded a new .env
  # variable: the container is recreated with the new environment, so the
  # poller must see the same one — otherwise the two disagree about what is
  # reachable, which is the mismatch that makes activation untrustworthy.
  if [[ -f "${POLLER_PID}" ]]; then
    local previous
    previous="$(cat "${POLLER_PID}")"
    if [[ -n "${previous}" ]]; then
      kill "${previous}" 2>/dev/null || true
    fi
    rm -f "${POLLER_PID}"
  fi
  # Detached, so it outlives `devbot up`; down.sh stops it through the PID file.
  # Output goes to its own log, never to the terminal.
  nohup bash "${MODULE_DIR}/poller.sh" >> "${RUNTIME_DIR}/refresh.log" 2>&1 &
  _ok "datasources — refresh poller started (every ${DATASOURCES_REFRESH_INTERVAL:-10}s)"
}

main() {
  _info "datasources — up"

  # Docker first: rendering now validates the candidate by running the pinned
  # toolbox, so a machine without docker cannot render — and has no gateway to
  # render for.
  if ! command -v docker >/dev/null 2>&1; then
    _warn "docker not found — datasources gateway not started."
    return 0
  fi

  bash "${MODULE_DIR}/render.sh"

  # Compose interpolates ${VAR} from THIS process's environment, and it only
  # auto-reads a .env beside the compose file — which is storage/, not the repo
  # root. Load the repo .env explicitly, for the same reason bin/up.sh does.
  if [[ -f "${DEV_BOT_ROOT}/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "${DEV_BOT_ROOT}/.env"
    set +a
  fi

  # Deliberately no --no-recreate (unlike the other gateways): the whole point
  # of this container is the credentials it is handed, so rotating a value in
  # .env must take effect on the next `devbot up` rather than silently requiring
  # a manual container removal. A tools.yaml edit needs no recreate at all —
  # toolbox hot-reloads a mounted config.
  if ! (
    cd "${RUNTIME_DIR}" &&
      DEV_UID="${DEV_UID:-$(id -u)}" DEV_GID="${DEV_GID:-$(id -g)}" \
      TOOLBOX_IMAGE="${TOOLBOX_IMAGE}" TOOLBOX_VERSION="${TOOLBOX_VERSION}" \
        docker compose -f "${COMPOSE_FILE}" up -d
  ); then
    _warn "datasources gateway failed to start — continuing without it."
    return 0
  fi

  _start_poller

  # An `if`, not `&&`: under `set -e` a short-circuited `&&` would abort here.
  if _devbot_wait_for_mcp_gateway datasources "${MCP_URL}"; then
    _ok "datasources gateway reachable at ${MCP_URL}"
  fi

  return 0
}

main "$@"
