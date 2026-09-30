#!/usr/bin/env bash
# src/agentic/datasources/reconcile.sh
# Converge the running sidecars to the live sessions' demand.
#
# Invoked by the session registry on a session's EXIT, while other sessions may
# still be live: a sidecar whose last consumer just left is stopped now rather
# than lingering until the next boot. It is the same rule up.sh applies at boot
# (see functions.sh), so the two converge.
#
# The caller holds the registry lock and exports _DEVBOT_REGISTRY_LOCK_HELD; this
# script takes no lock — it only talks to docker — so that flag is informational.
#
# Non-fatal by design: a failed reconcile must never fail a session exit.
set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "${MODULE_DIR}/../../.." && pwd)}"
export DEV_BOT_ROOT

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

main() {
  command -v docker >/dev/null 2>&1 || return 0
  docker info >/dev/null 2>&1 || return 0

  local wanted
  # shellcheck disable=SC2046  # project paths are space-free; split on purpose
  if ! wanted="$(_wanted_sidecars $(_devbot_live_session_projects))"; then
    _warn "datasources — could not read the catalogue; leaving the running sidecars untouched"
    return 0
  fi
  _reconcile_sidecars "${wanted}"
}

main "$@"
