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
# The previously-published config, kept OUTSIDE the conf dir on purpose:
# toolbox loads every .yaml/.yml in that dir, and a rollback target must never
# be one of them.
CONF_BACKUP="${RUNTIME_DIR}/tools.yaml.last"
# The gateway's fixed container name (compose.tpl.yml), used to confirm that a
# published config was actually accepted.
CONTAINER_NAME="dev-bot-datasources-mcp"
GLOBAL_CONFIG="${DEV_BOT_ROOT}/.devbot.global.jsonc"
# The reader lives beside this module, never under DEV_BOT_ROOT — which is
# overridden to a sandbox root in tests. Same reasoning as
# _devbot_get_disabled_modules.
READER="${MODULE_DIR}/../../_shared/read_jsonc.py"
# The oracle: runs the real toolbox against the candidate and keeps only the
# sources it can actually initialize. Overridable so the unit tests stay
# docker-free (they point this at a stub); production uses the real validator.
VALIDATOR="${DATASOURCES_VALIDATOR:-${MODULE_DIR}/validate_catalogue.py}"

# Confirm the running gateway accepted the reload. toolbox rejects a config it
# cannot initialize and keeps serving the previous one — but it retries the bad
# file on every poll interval, so a rejected publish is undone rather than left
# for the gateway to hammer.
#
# A single rejection is NOT enough to act on. `cp` truncates and rewrites the
# file in place, so toolbox can read a partial document mid-write and report a
# source failure for a config that is actually fine; only a rejection that
# survives one more reload cycle is treated as real.
#
# Skipped when the gateway is not running: install.sh and up.sh render before
# the container exists.
_verify_reload() {
  if ! docker inspect -f '{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null | grep -qx true; then
    return 0
  fi
  local wait="${DATASOURCES_RELOAD_WAIT:-6}"
  sleep "${wait}"
  if ! _reload_rejected; then
    return 0
  fi
  # One rejection may be a partial read of the in-place `cp`. If the file on
  # disk is good, the gateway's next retry succeeds and the rejections stop.
  sleep "${wait}"
  if ! _reload_rejected; then
    return 0
  fi

  local rejection
  rejection="$(docker logs --since "$(( wait + 1 ))s" "${CONTAINER_NAME}" 2>&1 |
    grep 'unable to initialize source' | tail -1 || true)"
  if [[ -f "${CONF_BACKUP}" ]]; then
    cp "${CONF_BACKUP}" "${CONF_DIR}/tools.yaml"
    _error "datasources — the gateway rejected the new config; rolled back. ${rejection}"
  else
    _error "datasources — the gateway rejected the new config with no previous one to restore. ${rejection}"
  fi
  return 1
}

# True when the gateway logged a source-initialization failure in the last
# reload cycle.
_reload_rejected() {
  docker logs --since "$(( ${DATASOURCES_RELOAD_WAIT:-6} + 1 ))s" "${CONTAINER_NAME}" 2>&1 |
    grep -q 'unable to initialize source'
}

main() {
  mkdir -p "${RUNTIME_DIR}"
  mkdir -p "${CONF_DIR}"

  # One render at a time: a manual `devbot up` and the detached poller must not
  # interleave publishes, the rollback backup, or the quarantine state. The lock
  # is held for this shell's lifetime. A cap of 0 means fail fast, not wait.
  if ! _devbot_lock_wait "${RUNTIME_DIR}/render.lock" "${DATASOURCES_RENDER_LOCK_WAIT:-60}"; then
    _error "datasources — another render is in progress; skipping this one"
    return 1
  fi

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
  #
  # A FAILED read is not the same thing. Swallowing it as "{}" is how a
  # transient read error once replaced a good config with an empty one and took
  # every toolset down. Abort instead — nothing is written, so the running
  # gateway keeps serving the last good config.
  local catalogue=""
  if [[ -f "${GLOBAL_CONFIG}" ]]; then
    if ! catalogue="$(python3 "${READER}" "${GLOBAL_CONFIG}" datasources)"; then
      _error "datasources — could not read the catalogue from ${GLOBAL_CONFIG}; keeping the last good config"
      return 1
    fi
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
  # Three stages: available_catalogue.py emits the env-complete subset as JSON;
  # validate_catalogue.py asks the real toolbox which of those it can actually
  # initialize, and emits the survivors; render_tools_yaml.py turns those into
  # the multi-document YAML toolbox reads. `pipefail` (set above) means a
  # failing stage aborts before anything is written, so a bad render can never
  # replace a working config.
  printf '%s' "${catalogue}" |
    python3 "${MODULE_DIR}/available_catalogue.py" |
    python3 "${VALIDATOR}" |
    python3 "${MODULE_DIR}/render_tools_yaml.py" > "${CONF_DIR}/tools.yaml.tmp"

  # Never replace a published config with an empty one. All declared sources
  # being unusable at once is a transient failure, not a removal — publishing
  # the empty render would take every toolset down. Two other cases are NOT
  # that failure and must still publish empty: the first render (nothing
  # published yet) so boot and the poller keep working, and a deliberate
  # removal (nothing declared) so it cannot deadlock.
  local declared previous_sources available
  declared="$(printf '%s' "${catalogue}" | python3 -c \
    'import json, sys; print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0)"
  previous_sources="$(grep -c '^kind: source' "${CONF_DIR}/tools.yaml" 2>/dev/null || true)"
  available="$(grep -c '^kind: source' "${CONF_DIR}/tools.yaml.tmp" || true)"
  if (( declared > 0 && available == 0 && previous_sources > 0 )); then
    rm -f "${CONF_DIR}/tools.yaml.tmp" "${RUNTIME_DIR}/docker-compose.yml.tmp"
    _error "datasources — all ${declared} declared datasource(s) are unusable; keeping the last good config"
    return 1
  fi

  # Nothing changed: skipping the publish also skips the reload — and the
  # verification wait — it would trigger.
  if [[ -f "${CONF_DIR}/tools.yaml" ]] &&
    cmp -s "${CONF_DIR}/tools.yaml.tmp" "${CONF_DIR}/tools.yaml"; then
    rm -f "${CONF_DIR}/tools.yaml.tmp"
    mv "${RUNTIME_DIR}/docker-compose.yml.tmp" "${RUNTIME_DIR}/docker-compose.yml"
    _skip "datasources — ${available}/${declared} datasource(s) usable; config unchanged"
    return 0
  fi

  # Keep the previous config so a rejected reload can be undone.
  if [[ -f "${CONF_DIR}/tools.yaml" ]]; then
    cp "${CONF_DIR}/tools.yaml" "${CONF_BACKUP}"
  fi

  # IN PLACE, never `mv`: toolbox tracks the config file by inode, so a
  # replaced file is invisible to its reloader and the change would silently
  # never take effect. `cp` truncates the destination, preserving the inode.
  # A transient partial read is harmless — toolbox rejects a bad reload and
  # keeps serving the previous config, and the poll picks up the final state.
  cp "${CONF_DIR}/tools.yaml.tmp" "${CONF_DIR}/tools.yaml"
  rm -f "${CONF_DIR}/tools.yaml.tmp"
  mv "${RUNTIME_DIR}/docker-compose.yml.tmp" "${RUNTIME_DIR}/docker-compose.yml"

  if ! _verify_reload; then
    return 1
  fi

  _ok "datasources — ${available}/${declared} datasource(s) usable, rendered into ${RUNTIME_DIR}"
}

main "$@"
