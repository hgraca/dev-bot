#!/usr/bin/env bash
# Shared helpers — delegates to src/_shared/functions.sh for boilerplate.

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_shared/functions.sh
source "${MODULE_DIR}/../../_shared/functions.sh"

# Print the opencode 2.x binary this harness launches, or nothing when absent.
#
# First executable wins: OPENCODE2_BIN (tests, custom installs), the shim
# dev-bot installs, the private 2.x install directory, then PATH. The v1 host at
# ~/.opencode/bin/opencode is deliberately never a candidate — the two lines run
# side by side on one machine.
_devbot_opencode2_bin() {
  local candidate
  for candidate in "${OPENCODE2_BIN:-}" \
                   "${HOME}/.opencode/bin/opencode2" \
                   "${HOME}/.opencode/v2/opencode"; do
    if [[ -n "${candidate}" && -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  candidate="$(command -v opencode2 2>/dev/null || true)"
  [[ -n "${candidate}" ]] && printf '%s\n' "${candidate}"
  return 0
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
  local bin raw version major
  bin="$(_devbot_opencode2_bin)"
  [[ -n "${bin}" ]] || return 0

  raw="$("${bin}" --version 2>/dev/null | head -n1)" || true
  # The 2.x binary prints "opencode v2.3.0" while the 1.x one printed a bare
  # "1.18.35", and release tags use the v-prefixed form. Strip both before
  # reading the major, or the fail-open branch quietly allows a 1.x host.
  version="${raw#opencode }"
  version="${version#v}"
  major="${version%%.*}"
  [[ "${major}" =~ ^[0-9]+$ ]] || major=""

  if [[ -z "${major}" ]]; then
    _warn "opencode2 version '${raw}' not recognised — cannot verify the 2.x plugin API; proceeding"
    return 0
  fi

  # A source build reports 0.0.0--<ts> and is allowed silently, as in the v1
  # guard; every other major must be 2, or the plugin API is unverified.
  [[ "${major}" -eq 0 ]] && return 0
  [[ "${major}" -eq 2 ]] && return 0

  if [[ "${major}" -eq 1 ]]; then
    _fatal "opencode ${raw} is not supported — the opencode-v2 harness targets the 2.x line."
    _fatal "  A 1.x host has no V2 plugin API, so this module's hooks and TUI parts do not load."
    _fatal "  Select harness 'opencode' for a 1.x host, or install opencode 2.x as opencode2."
    return 1
  fi

  _fatal "opencode ${raw} is not supported — the opencode-v2 harness targets the 2.x line."
  _fatal "  Major ${major} is unverified: the 2.x plugin API may differ or be absent."
  return 1
}
