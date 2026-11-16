#!/usr/bin/env bash
# Shared helpers — delegates to src/_shared/functions.sh for boilerplate.

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_shared/functions.sh
source "${MODULE_DIR}/../../_shared/functions.sh"

# Print the opencode 2.x binary this harness launches, or nothing when absent.
#
# Some machines install 2.x as plain `opencode`; others keep it beside a 1.x
# install as `opencode2`. So the plain name is probed first and only accepted
# when it actually reports the 2.x line — a 1.x `opencode` is the other
# harness's binary and must never be launched from here. OPENCODE2_BIN remains
# the explicit override (tests, custom installs).
_devbot_opencode2_bin() {
  local candidate

  if [[ -n "${OPENCODE2_BIN:-}" && -x "${OPENCODE2_BIN}" ]]; then
    printf '%s\n' "${OPENCODE2_BIN}"
    return 0
  fi

  candidate="$(command -v opencode 2>/dev/null || true)"
  if [[ -n "${candidate}" && -x "${candidate}" ]] && _devbot_opencode_is_2x "${candidate}"; then
    printf '%s\n' "${candidate}"
    return 0
  fi

  for candidate in "${HOME}/.opencode/bin/opencode2" \
                   "${HOME}/.opencode/v2/opencode" \
                   "$(command -v opencode2 2>/dev/null || true)"; do
    if [[ -n "${candidate}" && -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 0
}

# Print the major version a binary reports, or nothing when it cannot be read.
#
# The 2.x binary prints "opencode v2.3.0" while the 1.x one printed a bare
# "1.18.35", and release tags use the v-prefixed form. Strip both before
# reading the major, or a 1.x host slips through.
_devbot_opencode_major() {
  local bin="$1" raw version
  [[ -n "${bin}" && -x "${bin}" ]] || return 0
  raw="$("${bin}" --version 2>/dev/null | head -n1)" || true
  version="${raw#opencode }"
  version="${version#v}"
  printf '%s\n' "${version%%.*}"
  return 0
}

# True when a binary reports the 2.x line (or a source build's 0.0.0).
_devbot_opencode_is_2x() {
  local major
  major="$(_devbot_opencode_major "$1")"
  [[ "${major}" == "2" || "${major}" == "0" ]]
}

# Refuse an opencode 1.x host.
#
# This module's plugin surface — hooks/on-hooks.ts, hooks/mcp-sync.ts and the
# packaged TUI parts — is the opencode V2 plugin API. A 1.x host loads none of
# it while the seeded config still applies, which is a silent half-working
# install; refusing loudly is the only honest outcome.
#
# Two call sites, mirroring v1's guard: up.sh surfaces it on `devbot` /
# `make up`, and start.sh is the one that actually refuses — _run_service_scripts
# swallows a module up.sh's non-zero exit.
#
# Fail-open on a missing binary (start.sh reports that itself) and on a version
# this cannot parse. Only the 1.x line is refused: a source build reporting
# 0.0.0--<timestamp> parses to a major of 0 and is allowed silently.
_devbot_require_opencode_2x() {
  local bin raw major
  bin="$(_devbot_opencode2_bin)"
  [[ -n "${bin}" ]] || return 0

  raw="$("${bin}" --version 2>/dev/null | head -n1)" || true
  major="$(_devbot_opencode_major "${bin}")"
  [[ "${major}" =~ ^[0-9]+$ ]] || major=""

  if [[ -z "${major}" ]]; then
    _warn "${bin} version '${raw}' not recognised — cannot verify the 2.x plugin API; proceeding"
    return 0
  fi

  # A source build reports 0.0.0--<ts> and is allowed silently, as in the v1
  # guard; every other major must be 2, or the plugin API is unverified.
  [[ "${major}" -eq 0 ]] && return 0
  [[ "${major}" -eq 2 ]] && return 0

  if [[ "${major}" -eq 1 ]]; then
    _fatal "${bin} reports ${raw} — the opencode-v2 harness targets the 2.x line."
    _fatal "  A 1.x host has no V2 plugin API, so this module's hooks and TUI parts do not load."
    _fatal "  Select harness 'opencode' for a 1.x host, or install opencode 2.x (as opencode or opencode2)."
    return 1
  fi

  _fatal "${bin} reports ${raw} — the opencode-v2 harness targets the 2.x line."
  _fatal "  Major ${major} is unverified: the 2.x plugin API may differ or be absent."
  return 1
}
