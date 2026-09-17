#!/usr/bin/env bash
# src/agentic/datasources/poller.sh
# Keeps the gateway's tools.yaml in step with what is actually reachable.
#
# Toolbox initialises sources eagerly and treats an unreachable or
# env-incomplete source as a FATAL error, so the config may only ever contain
# usable datasources. This loop re-checks availability and re-renders when the
# usable set changes; toolbox hot-reloads the rewritten config, so a database
# that comes up after `devbot up` activates WITHOUT a restart, and one that
# goes away simply drops out.
#
# Started detached by up.sh, stopped by down.sh through refresh.pid.
# It renders only when the usable set actually changes, so the log stays
# readable instead of gaining a line every interval.
set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "${MODULE_DIR}/../../.." && pwd)}"
export DEV_BOT_ROOT

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

RUNTIME_DIR="${DEV_BOT_ROOT}/storage/datasources"
LOG="${RUNTIME_DIR}/refresh.log"
PIDFILE="${RUNTIME_DIR}/refresh.pid"
INTERVAL="${DATASOURCES_REFRESH_INTERVAL:-10}"
GLOBAL_CONFIG="${DEV_BOT_ROOT}/.devbot.global.jsonc"
READER="${DEV_BOT_ROOT}/src/_shared/read_jsonc.py"

# The usable datasource names, space-separated, in a stable order. Comparing
# this string is what tells the loop whether anything actually changed.
_available_names() {
  local catalogue="{}"
  if [[ -f "${GLOBAL_CONFIG}" ]]; then
    catalogue="$(python3 "${READER}" "${GLOBAL_CONFIG}" datasources 2>/dev/null || true)"
  fi
  [[ -z "${catalogue}" || "${catalogue}" == "null" ]] && catalogue="{}"

  printf '%s' "${catalogue}" |
    python3 "${MODULE_DIR}/available_catalogue.py" 2>/dev/null |
    python3 -c 'import json, sys; print(" ".join(sorted(json.load(sys.stdin))))' 2>/dev/null || true
}

main() {
  mkdir -p "${RUNTIME_DIR}"

  # The same environment render.sh and the container work from, so the
  # availability set this loop compares is the one that will actually be
  # rendered. Without it, values held in the repo .env would look missing and
  # the loop would believe nothing ever changes.
  if [[ -f "${DEV_BOT_ROOT}/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "${DEV_BOT_ROOT}/.env"
    set +a
  fi

  printf '%s\n' "$$" > "${PIDFILE}"
  trap 'rm -f "${PIDFILE}"' EXIT

  # A sentinel, so the first pass always renders and syncs the config to
  # reality rather than trusting whatever is on disk.
  local previous="__unset__"

  while true; do
    local now
    now="$(_available_names)"
    if [[ "${now}" != "${previous}" ]]; then
      {
        printf '%s usable: [%s]\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${now}"
        bash "${MODULE_DIR}/render.sh" || printf 'render failed\n'
      } >> "${LOG}" 2>&1
      previous="${now}"
    fi
    sleep "${INTERVAL}"
  done
}

main "$@"
