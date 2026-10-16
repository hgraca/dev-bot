#!/usr/bin/env bash
# Shared helpers — delegates to src/_shared/functions.sh for boilerplate.

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_shared/functions.sh
source "${MODULE_DIR}/../../_shared/functions.sh"

# Refuse an opencode 2.x host.
#
# dev-bot's whole plugin surface — the server hooks in hooks/on-hooks.ts and the
# TUI plugins (pty-monitor, tui-defaults) — is the opencode V1 plugin API, which
# v2 replaced. On a v2 host none of it loads while the seeded config still
# applies: a silent half-working install. Refuse it loudly instead.
#
# Two call sites: up.sh surfaces it on `devbot` / `make up`, and start.sh gates
# the launch. start.sh is the one that actually refuses — _run_service_scripts
# swallows a module up.sh's non-zero exit (it counts it as "had issues" and
# returns 0), so up.sh alone cannot stop the start sequence.
#
# Fail-open on everything but a confidently-detected 2.x: a missing binary is
# start.sh's own error to report, and a version this cannot parse (no leading
# digit) is warned about, never fatal. A source build reporting 0.0.0--<ts>
# parses to a major of 0 and is allowed silently.
_devbot_require_opencode_1x() {
  local bin="${HOME}/.opencode/bin/opencode"
  [[ -x "${bin}" ]] || return 0

  local version major
  version="$("${bin}" --version 2>/dev/null | head -n1)" || true
  # Strip an optional leading `v` first: opencode's tags and changelog use the
  # v-prefixed form (v2.0.30), and a version that fails to match falls through
  # to the fail-open warn branch — silently allowing the host this exists to
  # refuse.
  major="$(printf '%s' "${version}" | sed -n 's/^v//; s/^\([0-9][0-9]*\).*/\1/p')"

  if [[ -z "${major}" ]]; then
    _warn "opencode version '${version}' not recognised — cannot verify the 1.x plugin API; proceeding"
    return 0
  fi

  if [[ "${major}" -ge 2 ]]; then
    _fatal "opencode ${version} is not supported — dev-bot targets the opencode 1.x line."
    _fatal "  A v2 host uses a new plugin API, so dev-bot's hooks and TUI plugins do not load,"
    _fatal "  the server API contracts changed, and tui.json moved to a global cli.json."
    _fatal "  Install opencode 1.x (the default installer still ships 1.x) and relaunch."
    return 1
  fi

  return 0
}
