#!/usr/bin/env bash
# =============================================================================
# src/agentic/forensics/sources/github/plugin.sh
# GitHub pull-request source adapter for the forensics module.
#
# Contract (mirrors the language plugins): meta | doctor | fetch.
#   meta    print {"source","capabilities"}
#   doctor  report whether the authenticated `gh` CLI is available
#   fetch   read {"project","since","until"} on stdin and emit
#           {"ok","pull_requests":[{"number","author","created_at","merged_at",
#           "commits","added","deleted","changed_files","url"}],"errors"}
#
# JSON never crosses bash: plugin.py owns the request and response.
# GATE: must run on Ubuntu, Fedora and macOS — no GNU-only tools, no `readlink -f`.
# =============================================================================

set -euo pipefail

_resolve_self() {
  local target="${BASH_SOURCE[0]}" dir link
  while [[ -L "${target}" ]]; do
    dir="$(cd -P "$(dirname "${target}")" && pwd)"
    link="$(readlink "${target}")"
    [[ "${link}" != /* ]] && link="${dir}/${link}"
    target="${link}"
  done
  cd -P "$(dirname "${target}")" && pwd
}

PLUGIN_DIR="$(_resolve_self)"
exec python3 "${PLUGIN_DIR}/plugin.py" "$@"
