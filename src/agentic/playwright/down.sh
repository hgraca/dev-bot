#!/usr/bin/env bash
# src/agentic/playwright/down.sh
# Reaps playwright MCP containers left behind by a session that died.
#
# Every launch is `docker run --rm -i`, so a clean client exit removes its own
# container. An abrupt client death (session kill/crash) leaves the container
# attached to a dead stdin instead, and `--rm` never fires — so they accumulate
# (audit-01 NOTE-5).
#
# The launch tags each container with LABEL, so this touches only containers
# dev-bot started: an `mcp/playwright` run by hand is left alone. The compose
# project filter is not an option here — these containers are not compose-managed
# (proven: `docker compose down --remove-orphans` needs the full fabricated
# com.docker.compose.* label set, config-hash included, to collect one).
#
# bin/down.sh discovers this script like any other module down.sh, which means it
# is skipped when the module is disabled: a container orphaned while playwright
# was enabled and then disabled is not collected here. That case has no
# collection point, so it is a documented manual step:
#
#   docker ps -aq --filter label=dev-bot.mcp=playwright | xargs -r docker rm -f
#
# Non-fatal by design: a container that will not die must not fail `devbot down`.
set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "${MODULE_DIR}/../../.." && pwd)}"
export DEV_BOT_ROOT

# This module ships no functions.sh — source the shared library directly, as
# bin/down.sh does.
# shellcheck source=../../_shared/functions.sh
source "${DEV_BOT_ROOT}/src/_shared/functions.sh"

# Must stay in step with the --label in mcp.json; the BATS suite pins the two
# together, because a one-sided edit silently stops collecting orphans.
LABEL="dev-bot.mcp=playwright"

main() {
  if ! command -v docker >/dev/null 2>&1; then
    _skip "playwright — docker not found, nothing to reap"
    return 0
  fi

  local ids
  # -a, not just running: a client death usually strands the container still
  # attached to a dead stdin (which is exactly what the audit saw), but one that
  # exited without `--rm` firing is equally garbage. Nothing else manages these.
  ids="$(docker ps -aq --filter "label=${LABEL}" 2>/dev/null || true)"
  if [[ -z "${ids}" ]]; then
    _skip "playwright — no orphaned containers"
    return 0
  fi

  # Count only what was actually removed: a stubborn container must not fail
  # `devbot down`, but neither may the summary claim it was reaped.
  local count=0 id
  while IFS= read -r id; do
    [[ -n "${id}" ]] || continue
    if docker rm -f "${id}" >/dev/null 2>&1; then
      count=$((count + 1))
    else
      _warn "playwright — could not remove container ${id}"
    fi
  done <<< "${ids}"

  _ok "playwright — reaped ${count} orphaned container(s)"
  return 0
}

main "$@"
