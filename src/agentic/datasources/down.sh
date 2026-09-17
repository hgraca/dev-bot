#!/usr/bin/env bash
# src/agentic/datasources/down.sh
# Stops the datasource gateway.
#
# The compose file is the one render.sh generates into storage/datasources/, so
# bin/down.sh's compose discovery does not see it — see up.sh for why.
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

# Stop the availability poller first: leaving it running would keep rewriting
# the config for a gateway that is no longer up.
_stop_poller() {
  if [[ ! -f "${POLLER_PID}" ]]; then
    return 0
  fi
  local pid
  pid="$(cat "${POLLER_PID}")"
  if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
    kill "${pid}" 2>/dev/null && _ok "datasources — refresh poller stopped"
  fi
  rm -f "${POLLER_PID}"
}

main() {
  _stop_poller

  if [[ ! -f "${COMPOSE_FILE}" ]]; then
    _skip "datasources — no generated compose file, nothing to stop"
    return 0
  fi
  if ! command -v docker >/dev/null 2>&1; then
    _skip "datasources — docker not found, nothing to stop"
    return 0
  fi

  # The image vars are supplied so compose can interpolate the file without
  # emitting "variable is not set" warnings on the way down.
  if (
    cd "${RUNTIME_DIR}" &&
      TOOLBOX_IMAGE="${TOOLBOX_IMAGE}" TOOLBOX_VERSION="${TOOLBOX_VERSION}" \
        docker compose -f "${COMPOSE_FILE}" down
  ); then
    _ok "datasources gateway stopped"
  else
    _warn "datasources gateway could not be stopped cleanly."
  fi
}

main "$@"
