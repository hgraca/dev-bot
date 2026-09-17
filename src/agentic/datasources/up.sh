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
DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "${MODULE_DIR}/../.." && pwd)}"
export DEV_BOT_ROOT

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

# shellcheck source=./versions.env
source "${MODULE_DIR}/versions.env"

RUNTIME_DIR="${DEV_BOT_ROOT}/storage/datasources"
COMPOSE_FILE="${RUNTIME_DIR}/docker-compose.yml"
MCP_URL="${DATASOURCES_MCP_URL:-http://127.0.0.1:18510/mcp}"

main() {
  _info "datasources — up"

  bash "${MODULE_DIR}/render.sh"

  if ! command -v docker >/dev/null 2>&1; then
    _warn "docker not found — datasources gateway not started."
    return 0
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

  # An `if`, not `&&`: under `set -e` a short-circuited `&&` would abort here.
  if _devbot_wait_for_mcp_gateway datasources "${MCP_URL}"; then
    _ok "datasources gateway reachable at ${MCP_URL}"
  fi

  return 0
}

main "$@"
