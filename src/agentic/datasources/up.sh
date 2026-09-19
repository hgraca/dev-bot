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
# A poller left behind by an older dev-bot. Refresh is no longer backgrounded —
# datasources are evaluated once, at startup — so the only poller that can
# exist is one an older install started and never stopped. It is detached, so
# it would outlive the upgrade and keep rewriting the config for the gateway we
# are about to restart.
LEGACY_POLLER_PID="${RUNTIME_DIR}/refresh.pid"
MCP_URL="http://127.0.0.1:${DATASOURCES_PORT:-18510}/mcp"

_stop_legacy_poller() {
  [[ -f "${LEGACY_POLLER_PID}" ]] || return 0
  local previous
  previous="$(cat "${LEGACY_POLLER_PID}")"
  if [[ -n "${previous}" ]]; then
    kill "${previous}" 2>/dev/null || true
  fi
  rm -f "${LEGACY_POLLER_PID}"
}

# Take the gateway down before rendering. render.sh verifies a publish against
# a RUNNING gateway by waiting a reload interval — twice, if the first read
# looks like a rejection — so a container left over from the previous session
# would add that wait to every boot. Rendering cold also guarantees the
# container comes back up on the config just validated, rather than depending
# on toolbox to hot-reload it.
_stop_gateway() {
  [[ -f "${COMPOSE_FILE}" ]] || return 0
  (
    cd "${RUNTIME_DIR}" &&
      TOOLBOX_IMAGE="${TOOLBOX_IMAGE}" TOOLBOX_VERSION="${TOOLBOX_VERSION}" \
        docker compose -f "${COMPOSE_FILE}" down
  ) >/dev/null 2>&1 || true
}

# The gateway's container name, read from the template so compose.tpl.yml stays
# the single source of truth for it.
_container_name() {
  grep -m1 '^[[:space:]]*container_name:' "${MODULE_DIR}/compose.tpl.yml" | awk '{print $2}'
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

  # Both must be gone before render.sh runs: the legacy poller would race it,
  # and a running gateway would make it pay the reload-verification wait.
  _stop_legacy_poller
  _stop_gateway

  # Rendering validates the candidate against the real toolbox, which can fail
  # (an unreadable catalogue, docker down, or an inconclusive run). Keep going
  # with the config already on disk: a gateway up on the last good config beats
  # no gateway at all, and the next `devbot up` re-renders.
  if ! bash "${MODULE_DIR}/render.sh"; then
    _warn "datasources — render failed; starting the gateway with the previous config."
  fi

  # Compose interpolates ${VAR} from THIS process's environment, and it only
  # auto-reads a .env beside the compose file — which is storage/, not the repo
  # root. Load the repo .env explicitly, for the same reason bin/up.sh does.
  if [[ -f "${DEV_BOT_ROOT}/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "${DEV_BOT_ROOT}/.env"
    set +a
  fi

  # No --no-recreate (unlike the other gateways): the whole point of this
  # container is the credentials it is handed, so rotating a value in .env must
  # take effect on the next `devbot up` rather than silently requiring a manual
  # container removal. The gateway was taken down above, so this always starts
  # it fresh on the config render.sh just validated.
  if ! (
    cd "${RUNTIME_DIR}" &&
      DEV_UID="${DEV_UID:-$(id -u)}" DEV_GID="${DEV_GID:-$(id -g)}" \
      TOOLBOX_IMAGE="${TOOLBOX_IMAGE}" TOOLBOX_VERSION="${TOOLBOX_VERSION}" \
        docker compose -f "${COMPOSE_FILE}" up -d
  ); then
    _warn "datasources gateway failed to start — continuing without it."
    return 0
  fi

  # An `if`, not `&&`: under `set -e` a short-circuited `&&` would abort here.
  # The container name lets the wait stop as soon as the gateway has exited,
  # instead of retrying a URL nothing can answer.
  if _devbot_wait_for_mcp_gateway datasources "${MCP_URL}" "" "$(_container_name)"; then
    _ok "datasources gateway reachable at ${MCP_URL}"
  fi

  return 0
}

main "$@"
