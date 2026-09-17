#!/usr/bin/env bash
# src/agentic/datasources/render.sh
# Renders the gateway's runtime artifacts from the `datasources` catalogue in
# .devbot.global.jsonc:
#
#   storage/datasources/tools.yaml          one source + tool + toolset per datasource
#   storage/datasources/docker-compose.yml  the gateway, carrying env var NAMES
#
# Both are written atomically (temp file + mv) so a render failure never leaves
# the running gateway pointed at a half-written configuration.
#
# Invoked by install.sh, update.sh and up.sh. Not auto-discovered: the generic
# module runner only runs install/update/init/uninstall/up/down/pre/reset.
set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "${MODULE_DIR}/../.." && pwd)}"
export DEV_BOT_ROOT

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

RUNTIME_DIR="${DEV_BOT_ROOT}/storage/datasources"
GLOBAL_CONFIG="${DEV_BOT_ROOT}/.devbot.global.jsonc"
READER="${DEV_BOT_ROOT}/src/_shared/read_jsonc.py"

main() {
  mkdir -p "${RUNTIME_DIR}"
  # Where file-backed engines (sqlite) keep their databases — the compose
  # template mounts this at /data. Created as the host user, which is also the
  # uid/gid the container runs as, so it can write there.
  mkdir -p "${RUNTIME_DIR}/data"

  # read_jsonc.py prints nothing when the key is absent — a machine with no
  # datasources declared. The renderers treat that as an empty catalogue.
  local catalogue="{}"
  if [[ -f "${GLOBAL_CONFIG}" ]]; then
    catalogue="$(python3 "${READER}" "${GLOBAL_CONFIG}" datasources 2>/dev/null || true)"
  fi
  [[ -z "${catalogue}" || "${catalogue}" == "null" ]] && catalogue="{}"

  printf '%s' "${catalogue}" |
    python3 "${MODULE_DIR}/render_tools_yaml.py" > "${RUNTIME_DIR}/tools.yaml.tmp"
  printf '%s' "${catalogue}" |
    python3 "${MODULE_DIR}/render_compose.py" "${MODULE_DIR}/compose.tpl.yml" \
      > "${RUNTIME_DIR}/docker-compose.yml.tmp"

  mv "${RUNTIME_DIR}/tools.yaml.tmp" "${RUNTIME_DIR}/tools.yaml"
  mv "${RUNTIME_DIR}/docker-compose.yml.tmp" "${RUNTIME_DIR}/docker-compose.yml"

  local count
  count="$(printf '%s' "${catalogue}" | python3 -c \
    'import json, sys; print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0)"
  _ok "datasources — rendered ${count} datasource(s) into ${RUNTIME_DIR}"
}

main "$@"
