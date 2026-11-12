#!/usr/bin/env bash
# =============================================================================
# src/agentic/autobot/install.sh
# Registers the once-a-minute cron entry that drives `autobot tick`.
#
# The user's own crontab, never root's: the tick needs that user's opencode
# store, gh credentials and checkouts. Cron runs with a bare PATH and no shell
# profile, so the line carries both.
#
# Idempotent: the block between the markers is replaced, never duplicated.
#
# GATE: This module must work on Ubuntu, Fedora, and macOS.
# =============================================================================

set -euo pipefail

# shellcheck source=./functions.sh
source "$(dirname "${BASH_SOURCE[0]}")/functions.sh"

MARKER_BEGIN="# >>> devbot:autobot >>>"
MARKER_END="# <<< devbot:autobot <<<"

main() {
  _info "autobot — cron registration"

  if [[ "${DEV_BOT_AUTOBOT:-on}" == "off" ]]; then
    _skip "DEV_BOT_AUTOBOT=off — not registering the cron entry"
    return 0
  fi

  if (( EUID == 0 )) && [[ "${DEV_BOT_AUTOBOT_ALLOW_ROOT:-0}" != "1" ]]; then
    _error "refusing to register the cron entry as root"
    _info "run 'devbot install' as the user who runs devbot — root's crontab has no ~/.local/share/opencode, no gh login and no checkouts"
    return 1
  fi

  local crontab="${DEV_BOT_CRONTAB:-crontab}"
  if ! command -v "${crontab}" >/dev/null 2>&1; then
    _error "crontab not found — install a cron daemon, then re-run"
    return 1
  fi

  local devbot="${DEV_BOT_ROOT}/bin/devbot"
  if [[ ! -x "${devbot}" ]]; then
    _error "devbot entrypoint not found at ${devbot}"
    return 1
  fi

  local log_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/devbot"
  if ! mkdir -p "${log_dir}" 2>/dev/null; then
    _error "cannot create the log directory ${log_dir}"
    return 1
  fi
  local log="${log_dir}/autobot.log"

  # Cron has a bare PATH, so take the real locations — opencode and gh are routinely outside
  # /usr/bin (Homebrew, ~/.opencode/bin, linuxbrew).
  local -a bin_dirs=("${HOME}/.local/bin" "${HOME}/.bun/bin" "${HOME}/.opencode/bin" "/usr/local/bin" "/usr/bin" "/bin")
  local tool resolved
  for tool in bun opencode gh; do
    resolved="$(command -v "${tool}" 2>/dev/null || true)"
    if [[ -n "${resolved}" ]]; then bin_dirs+=("$(dirname "${resolved}")"); fi
  done
  local path="" dir
  for dir in "${bin_dirs[@]}"; do
    case ":${path}:" in *":${dir}:"*) continue ;; esac
    path="${path:+${path}:}${dir}"
  done
  local env_file="${XDG_CONFIG_HOME:-${HOME}/.config}/devbot/autobot.env"

  # The entry sources this file as shell code and it holds the Jira token.
  if [[ ! -f "${env_file}" ]]; then
    _warn "no credentials file at ${env_file} — the cron entries will exit until it exists"
  else
    local mode
    mode="$(python3 -c 'import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "${env_file}" 2>/dev/null || true)"
    if [[ -z "${mode}" ]]; then
      _error "cannot read the mode of ${env_file} — refusing to schedule a file it cannot verify"
      return 1
    fi
    if [[ "${mode}" != "0o600" ]]; then
      _error "${env_file} is ${mode} — it holds a token and is sourced as code"
      _info "fix it first: chmod 600 ${env_file}"
      return 1
    fi
  fi
  local schedule="* * * * *"
  local cleanup_schedule="17 3 * * *"

  # Cron has no environment of its own, so the credentials file is sourced by the entry itself.
  local tick_cmd
  tick_cmd="[ -f \"${env_file}\" ] && . \"${env_file}\"; cd \"${DEV_BOT_ROOT}\" && exec \"${devbot}\" tool autobot tick >> \"${log}\" 2>&1"
  local cleanup_cmd
  cleanup_cmd="[ -f \"${env_file}\" ] && . \"${env_file}\"; cd \"${DEV_BOT_ROOT}\" && exec \"${devbot}\" tool autobot cleanup >> \"${log}\" 2>&1"

  # The values are interpolated into a single-quoted sh -c string, so a quote, space or shell
  # metacharacter in any of them would rewrite the command cron runs.
  local unsafe=""
  local value
  for value in "${DEV_BOT_ROOT}" "${devbot}" "${log}" "${env_file}" ${path//:/ }; do
    if [[ "${value}" =~ [^A-Za-z0-9_./:@+-] ]]; then
      unsafe="${value}"
      break
    fi
  done
  if [[ -n "${unsafe}" ]]; then
    _error "refusing to write a crontab with an unsafe path: ${unsafe}"
    _info "move them to a path without spaces, quotes, % or other shell metacharacters"
    return 1
  fi

  local entry="${schedule} PATH=${path} /bin/sh -c '${tick_cmd}'"
  local cleanup_entry="${cleanup_schedule} PATH=${path} /bin/sh -c '${cleanup_cmd}'"

  local current filtered tmp
  current="$("${crontab}" -l 2>/dev/null || true)"
  filtered="$(printf '%s\n' "${current}" | awk -v begin="${MARKER_BEGIN}" -v end="${MARKER_END}" '
    $0 == begin { skipping = 1; next }
    $0 == end { skipping = 0; next }
    !skipping { print }
  ')"

  tmp="$(mktemp)"
  {
    if [[ -n "${filtered}" ]]; then
      printf '%s\n' "${filtered}"
    fi
    printf '%s\n%s\n%s\n%s\n' "${MARKER_BEGIN}" "${entry}" "${cleanup_entry}" "${MARKER_END}"
  } >"${tmp}"

  if ! "${crontab}" "${tmp}"; then
    rm -f "${tmp}"
    _error "could not install the crontab"
    return 1
  fi
  rm -f "${tmp}"

  if "${crontab}" -l 2>/dev/null | grep -Fq "${entry}"; then
    _ok "autobot tick scheduled every minute (log: ${log})"
    return 0
  fi

  _error "the cron entry was written but is not visible in the crontab"
  return 1
}

main "$@"
