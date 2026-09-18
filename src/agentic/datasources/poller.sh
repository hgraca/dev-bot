#!/usr/bin/env bash
# src/agentic/datasources/poller.sh
# Keeps the gateway's tools.yaml in step with what the oracle accepts.
#
# Toolbox initialises sources eagerly and treats a source it cannot initialize
# as a FATAL error, so the config may only ever contain sources it accepts.
# render.sh decides that against the real toolbox; this loop decides WHEN to
# re-render:
#
#   * the env-complete candidate set changed, or
#   * quarantine.py says a re-validation is due — a parked source's backoff
#     elapsed, or the periodic re-validation came round (which is how a source
#     that died while published is eventually pruned, and one that came back is
#     re-added).
#
# toolbox hot-reloads the rewritten config, so a database that comes up after
# `devbot up` activates WITHOUT a restart, and one that goes away drops out.
#
# Started detached by up.sh, stopped by down.sh through refresh.pid.
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
# Beside this module, not under DEV_BOT_ROOT (sandboxed in tests).
READER="${MODULE_DIR}/../../_shared/read_jsonc.py"

# The usable datasource names, space-separated, in a stable order. Comparing
# this string is what tells the loop whether anything actually changed.
_available_names() {
  local catalogue
  if [[ -f "${GLOBAL_CONFIG}" ]]; then
    # A failed read returns non-zero so the caller skips the cycle. Treating it
    # as an empty set is what let a transient read failure publish an empty
    # config over a good one.
    catalogue="$(python3 "${READER}" "${GLOBAL_CONFIG}" datasources)" || return 1
  else
    catalogue="{}"
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
  local state_file="${RUNTIME_DIR}/quarantine.json"
  local validate_interval="${DATASOURCES_VALIDATE_INTERVAL:-300}"

  while true; do
    local now
    if ! now="$(_available_names)"; then
      # The catalogue could not be read, so the candidate set is unknown.
      # Publish nothing and leave the last good config serving. Log once per
      # failure spell rather than every cycle.
      if [[ "${previous}" != "__read_failed__" ]]; then
        printf '%s WARN: could not read the datasource catalogue; leaving the config untouched\n' \
          "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${LOG}"
        previous="__read_failed__"
      fi
      sleep "${INTERVAL}"
      continue
    fi

    local changed=0
    if [[ "${now}" != "${previous}" ]]; then
      changed=1
    fi
    # No state file yet means no render has validated anything: the set-change
    # path already covers the first render.
    local due=0
    if [[ -f "${state_file}" ]] &&
      python3 "${MODULE_DIR}/quarantine.py" needs-revalidation "${state_file}" "${validate_interval}"; then
      due=1
    fi

    if (( changed || due )); then
      {
        if (( changed )); then
          printf '%s usable: [%s]\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${now}"
        else
          printf '%s revalidating: [%s]\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${now}"
        fi
        bash "${MODULE_DIR}/render.sh" || printf 'render failed\n'
      } >> "${LOG}" 2>&1
      previous="${now}"
    fi
    sleep "${INTERVAL}"
  done
}

main "$@"
