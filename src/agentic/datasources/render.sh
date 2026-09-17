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
DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "${MODULE_DIR}/../../.." && pwd)}"
export DEV_BOT_ROOT

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

RUNTIME_DIR="${DEV_BOT_ROOT}/storage/datasources"
# The gateway mounts this directory and reads it with --config-folder. A
# directory (not the file) is what makes a replaced config visible: a
# bind-mounted file keeps pointing at the inode `mv` replaced.
CONF_DIR="${RUNTIME_DIR}/conf"
GLOBAL_CONFIG="${DEV_BOT_ROOT}/.devbot.global.jsonc"
# The reader lives beside this module, never under DEV_BOT_ROOT — which is
# overridden to a sandbox root in tests. Same reasoning as
# _devbot_get_disabled_modules.
READER="${MODULE_DIR}/../../_shared/read_jsonc.py"

main() {
  mkdir -p "${RUNTIME_DIR}"
  mkdir -p "${CONF_DIR}"

  # The availability filter must see the SAME environment the container gets.
  # Compose takes its values from the environment up.sh builds (which includes
  # the repo .env), so the filter has to read it too — otherwise a datasource
  # whose values live there is judged env-incomplete and never activates.
  if [[ -f "${DEV_BOT_ROOT}/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "${DEV_BOT_ROOT}/.env"
    set +a
  fi
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
    python3 "${MODULE_DIR}/render_compose.py" "${MODULE_DIR}/compose.tpl.yml" \
      > "${RUNTIME_DIR}/docker-compose.yml.tmp"

  # tools.yaml carries ONLY the datasources that are usable right now: toolbox
  # treats an env-incomplete or unreachable source as a fatal startup error, so
  # an unusable one in here would take the whole shared gateway down. Exclusion
  # reasons print to stderr (visible on `devbot up`, captured in the poller log).
  #
  # compose, by contrast, is rendered from the FULL catalogue: every
  # datasource's env vars must already be in the container when it later
  # becomes available, because a changed env list forces a container recreate —
  # which would defeat hot-reload activation.
  # Two stages: available_catalogue.py emits the usable subset as JSON, which
  # render_tools_yaml.py turns into the multi-document YAML toolbox reads.
  # `pipefail` (set above) means a failing filter aborts before the mv, so a
  # bad render can never replace a working config.
  printf '%s' "${catalogue}" |
    python3 "${MODULE_DIR}/available_catalogue.py" |
    python3 "${MODULE_DIR}/render_tools_yaml.py" > "${CONF_DIR}/tools.yaml.tmp"

  # IN PLACE, never `mv`: toolbox tracks the config file by inode, so a
  # replaced file is invisible to its reloader and the change would silently
  # never take effect. `cp` truncates the destination, preserving the inode.
  # A transient partial read is harmless — toolbox rejects a bad reload and
  # keeps serving the previous config, and the poll picks up the final state.
  cp "${CONF_DIR}/tools.yaml.tmp" "${CONF_DIR}/tools.yaml"
  rm -f "${CONF_DIR}/tools.yaml.tmp"
  mv "${RUNTIME_DIR}/docker-compose.yml.tmp" "${RUNTIME_DIR}/docker-compose.yml"

  local declared available
  declared="$(printf '%s' "${catalogue}" | python3 -c \
    'import json, sys; print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0)"
  available="$(grep -c '^kind: source' "${CONF_DIR}/tools.yaml" || true)"
  _ok "datasources — ${available}/${declared} datasource(s) usable, rendered into ${RUNTIME_DIR}"
}

main "$@"
