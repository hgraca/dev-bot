#!/usr/bin/env bash
# =============================================================================
# src/_shared/session_lock.sh
# Presence lock for a running devbot harness.
#
# One file per PID under <project>/<devbot_dir>/state/devbot/<pid>.json, written
# when the harness starts and removed when it exits. The `autobot` module reads
# these to decide whether devbot is running in a project. Liveness is the PID, so
# a crashed session leaves a file that is ignored rather than a false positive.
#
# Usage:
#   session_lock.sh create <project_dir> [kind]   # prints the lock path, empty on failure
#   session_lock.sh remove <lock_path>
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "${value}"
}

_create() {
  local project_dir="${1:?project directory required}"
  local kind="${2:-session}"
  # The harness passes its own pid: `$$` here is this short-lived helper, which is already gone by the
  # time a reader looks at the lock.
  local pid="${3:-$$}"
  local devbot_dir
  devbot_dir="$(python3 "${MODULE_DIR}/read_jsonc.py" "${project_dir}/.devbot.project.jsonc" devbot_dir 2>/dev/null || true)"
  if [[ -z "${devbot_dir}" && -n "${DEV_BOT_ROOT:-}" ]]; then
    devbot_dir="$(python3 "${MODULE_DIR}/read_jsonc.py" "${DEV_BOT_ROOT}/.devbot.global.jsonc" devbot_dir 2>/dev/null || true)"
  fi
  [[ -n "${devbot_dir}" ]] || devbot_dir=".agents"

  local state_dir="${project_dir}/${devbot_dir}/state/devbot"
  mkdir -p "${state_dir}" 2>/dev/null || return 0

  local lock="${state_dir}/${pid}.json"
  printf '{"pid":%d,"kind":"%s","project":"%s","harness":"%s","started_at":"%s"}\n' \
    "${pid}" \
    "$(_json_escape "${kind}")" \
    "$(_json_escape "${project_dir}")" \
    "$(_json_escape "${DEV_BOT_HARNESS:-unknown}")" \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    >"${lock}" 2>/dev/null || return 0
  printf '%s\n' "${lock}"
}

_remove() {
  local lock="${1:-}"
  if [[ -n "${lock}" && -f "${lock}" ]]; then
    rm -f "${lock}" 2>/dev/null || true
  fi
  return 0
}

case "${1:-}" in
  create)
    shift
    _create "$@"
    ;;
  remove)
    shift
    _remove "$@"
    ;;
  *)
    printf 'usage: session_lock.sh create <project_dir> [kind] | remove <lock_path>\n' >&2
    exit 2
    ;;
esac
