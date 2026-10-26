#!/usr/bin/env bash
# =============================================================================
# src/harnesses/opencode/lsp/reap.sh
# Reap the LSP servers opencode leaves behind, at wrap-up.
#
# opencode spawns one language server per directory it walks into and never
# tears a stale one down, so a long session accumulates idle `intelephense`,
# `yaml-language-server` and friends — each holding its own index in memory for
# the life of the process. They are reclaimed only by killing them; opencode
# respawns one on demand when the directory is visited again.
#
# Killing blindly is not safe: a server mid-index (or one a concurrent session
# in the same process is using) would be torn down and its work redone. So a
# server is reaped only when it is provably not working:
#   - its working directory no longer exists (its worktree was removed), or
#   - it burned no CPU between two samples one second apart.
# Everything else is left alone. The scan is scoped to one opencode process
# (and its descendants) — never machine-wide.
#
# Usage:
#   reap.sh [--parent <pid>] [--log <file>] [--dry-run]
#
#   --parent <pid>  reap under this pid (default: nearest opencode ancestor)
#   --log <file>    append decisions here (default: <DEV_BOT_ROOT>/.agents/logs/lsp-reap.log)
#   --dry-run       print the decision for each server, kill nothing
# =============================================================================

set -euo pipefail

DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)}"

# Language servers opencode can start. Matched against argv[0], or — for the
# interpreter-hosted ones (intelephense and the `*-language-server` packages run
# under node) — against the first argument, so a shell command that merely
# mentions a server name is never mistaken for one.
LSP_RE='(intelephense|language-server|language_server|gopls|pyright|rust-analyzer|clangd|solargraph|terraform-ls|marksman|taplo|emmet-ls|vscode-.*-language-features)'
INTERP_RE='^(node|nodejs|bun|deno|python|python3|java|dotnet)$'

DRY_RUN=false
PARENT_PID=""
LOG_FILE="${DEV_BOT_ROOT}/.agents/logs/lsp-reap.log"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --parent)
      [[ -n "${2:-}" ]] || { echo "reap.sh: --parent requires a <pid>" >&2; exit 1; }
      PARENT_PID="$2"
      shift 2
      ;;
    --log)
      [[ -n "${2:-}" ]] || { echo "reap.sh: --log requires a <file>" >&2; exit 1; }
      LOG_FILE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help | -h)
      sed -n '23,33p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "reap.sh: unknown argument '$1'" >&2
      exit 1
      ;;
  esac
done

# ── /proc readers ─────────────────────────────────────────────────────────────
# comm (stat field 2) is wrapped in parens and may itself contain spaces and
# parens, so everything is parsed from after the LAST ') '.
_ppid_of() {
  [[ -r "/proc/$1/stat" ]] || return 0
  awk '{ sub(/^.*\) /, ""); print $2 }' "/proc/$1/stat" 2>/dev/null || true
}

_cpu_ticks() {
  [[ -r "/proc/$1/stat" ]] || return 0
  awk '{ sub(/^.*\) /, ""); print $12 + $13 }' "/proc/$1/stat" 2>/dev/null || true
}

_cmdline_of() {
  [[ -r "/proc/$1/cmdline" ]] || return 0
  tr '\0' ' ' <"/proc/$1/cmdline" 2>/dev/null | sed 's/ $//' || true
}

# Prints "deleted" when the server's cwd is gone (a removed worktree), "live"
# when it still resolves to a directory, and "gone" when it cannot be read.
_cwd_state() {
  local link
  link="$(readlink "/proc/$1/cwd" 2>/dev/null || true)"
  if [[ -z "${link}" ]]; then
    printf 'gone'
  elif [[ "${link}" == *' (deleted)' || ! -d "${link}" ]]; then
    printf 'deleted'
  else
    printf 'live'
  fi
}

_is_lsp() {
  local pid="$1" line base arg i
  line="$(_cmdline_of "${pid}")"
  [[ -n "${line}" ]] || return 1
  local -a argv=()
  read -r -a argv <<<"${line}"
  [[ ${#argv[@]} -gt 0 ]] || return 1
  base="${argv[0]##*/}"
  [[ "${base}" =~ ${LSP_RE} ]] && return 0
  if [[ "${base}" =~ ${INTERP_RE} ]]; then
    for ((i = 1; i < ${#argv[@]} && i < 4; i++)); do
      arg="${argv[i]##*/}"
      [[ "${arg}" =~ ${LSP_RE} ]] && return 0
    done
  fi
  return 1
}

_name_of() {
  local pid="$1" line base
  line="$(_cmdline_of "${pid}")"
  local -a argv=()
  read -r -a argv <<<"${line}"
  [[ ${#argv[@]} -gt 0 ]] || { printf '?'; return; }
  base="${argv[0]##*/}"
  if [[ "${base}" =~ ${INTERP_RE} && ${#argv[@]} -gt 1 ]]; then
    printf '%s' "${argv[1]##*/}"
  else
    printf '%s' "${base}"
  fi
}

# ── Locate the opencode process to scan ───────────────────────────────────────
if [[ -z "${PARENT_PID}" ]]; then
  probe="$$"
  for _ in $(seq 1 40); do
    probe="$(_ppid_of "${probe}")"
    [[ -n "${probe}" && "${probe}" != "0" ]] || break
    if [[ "$(_cmdline_of "${probe}")" =~ (^|/)opencode([[:space:]]|$) ]]; then
      PARENT_PID="${probe}"
      break
    fi
  done
fi

# No opencode ancestor (the reaper was run by hand, or from another harness):
# there is nothing scoped to reap.
[[ -n "${PARENT_PID}" ]] || exit 0
[[ -d "/proc/${PARENT_PID}" ]] || exit 0

# ── Walk the descendant tree ──────────────────────────────────────────────────
declare -A _children=()
for _stat in /proc/[0-9]*/stat; do
  _pid="${_stat#/proc/}"
  _pid="${_pid%/stat}"
  _parent="$(_ppid_of "${_pid}")"
  [[ -n "${_parent}" ]] && _children["${_parent}"]+=" ${_pid}"
done

_candidates=()
_queue=("${PARENT_PID}")
while [[ ${#_queue[@]} -gt 0 ]]; do
  _next=()
  for _pid in "${_queue[@]}"; do
    _is_lsp "${_pid}" && _candidates+=("${_pid}")
    # shellcheck disable=SC2206 # deliberate word splitting of the child list
    [[ -n "${_children[${_pid}]:-}" ]] && _next+=(${_children[${_pid}]})
  done
  _queue=("${_next[@]:-}")
  [[ ${#_queue[@]} -gt 0 && -n "${_queue[0]:-}" ]] || break
done

[[ ${#_candidates[@]} -gt 0 ]] || exit 0

# ── Classify: deleted worktree wins, otherwise sample CPU ─────────────────────
declare -A _reason=()
_busy=()
for _pid in "${_candidates[@]}"; do
  case "$(_cwd_state "${_pid}")" in
    deleted | gone) _reason["${_pid}"]="deleted-cwd" ;;
    *) _busy+=("${_pid}") ;;
  esac
done

if [[ ${#_busy[@]} -gt 0 ]]; then
  declare -A _t0=() _t1=()
  for _pid in "${_busy[@]}"; do _t0["${_pid}"]="$(_cpu_ticks "${_pid}")"; done
  sleep 1
  for _pid in "${_busy[@]}"; do
    _t1["${_pid}"]="$(_cpu_ticks "${_pid}")"
    if [[ -n "${_t1[${_pid}]:-}" && "${_t1[${_pid}]}" == "${_t0[${_pid}]:-}" ]]; then
      _reason["${_pid}"]="idle"
    else
      _reason["${_pid}"]="busy"
    fi
  done
fi

# ── Act ───────────────────────────────────────────────────────────────────────
_log() {
  [[ "${DRY_RUN}" == true ]] && return 0
  mkdir -p "$(dirname "${LOG_FILE}")" 2>/dev/null || true
  printf '%s %s\n' "$(date -Is)" "$*" >>"${LOG_FILE}" 2>/dev/null || true
}

_reaped=0
for _pid in "${_candidates[@]}"; do
  _why="${_reason[${_pid}]:-busy}"
  _label="$(_name_of "${_pid}")"
  if [[ "${_why}" == "busy" ]]; then
    [[ "${DRY_RUN}" == true ]] && printf 'skipped %s %s (busy)\n' "${_pid}" "${_label}"
    _log "skipped ${_pid} ${_label} (busy)"
    continue
  fi
  if [[ "${DRY_RUN}" == true ]]; then
    printf 'would reap %s %s (%s)\n' "${_pid}" "${_label}" "${_why}"
    continue
  fi
  if kill -TERM "${_pid}" 2>/dev/null; then
    _reaped=$((_reaped + 1))
    _log "reaped ${_pid} ${_label} (${_why})"
  else
    _log "failed ${_pid} ${_label} (${_why}) — kill refused"
  fi
done

[[ "${DRY_RUN}" == true ]] && exit 0
[[ ${_reaped} -gt 0 ]] && _log "reaped ${_reaped} of ${#_candidates[@]} server(s) under ${PARENT_PID}"
exit 0
