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

RUNTIME_DIR="${DEV_BOT_ROOT}/storage/datasources"
COMPOSE_FILE="${RUNTIME_DIR}/docker-compose.yml"
LEGACY_POLLER_PID="${RUNTIME_DIR}/refresh.pid"

# A poller left behind by an older dev-bot. Refresh is no longer backgrounded
# (datasources are evaluated once, at startup), so this only ever reaps one an
# older install started — leaving it running would keep rewriting the config
# for a gateway that is no longer up.
_stop_legacy_poller() {
  if [[ ! -f "${LEGACY_POLLER_PID}" ]]; then
    return 0
  fi
  local pid
  pid="$(cat "${LEGACY_POLLER_PID}")"
  if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
    kill "${pid}" 2>/dev/null && _ok "datasources — stale refresh poller stopped"
  fi
  rm -f "${LEGACY_POLLER_PID}"
}

main() {
  # Before the compose check, not after it: a reload that is rendering its FIRST
  # compose file observes no file just like this does, so an unserialised no-op
  # here could return while the reload goes on to start containers — a teardown
  # that tears nothing down and still loses the race.
  #
  # Teardown is a lifecycle operation: it must not pull the gateway out from
  # under a reload that is verifying what it just rendered. Best effort by
  # design — a session exit must never hang — so a lock that cannot be had
  # within the cap warns and proceeds.
  #
  # The last-session teardown calls this with the REGISTRY lock held, while up.sh
  # takes the lifecycle lock and then waits for the registry lock: waiting here
  # would deadlock the two. Under the registry lock the acquisition is therefore
  # non-blocking, and a miss proceeds straight to the stop.
  if [[ -n "${_DEVBOT_REGISTRY_LOCK_HELD:-}" ]]; then
    DATASOURCES_LOCK_WAIT=0 _datasources_lock ||
      _warn "datasources — another lifecycle run is in progress; stopping anyway"
  elif ! _datasources_lock; then
    _warn "datasources — another lifecycle run is in progress; stopping anyway"
  fi

  _stop_legacy_poller

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
