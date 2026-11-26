#!/usr/bin/env bash
# =============================================================================
# src/agentic/playwright/up.sh
# Brings the shared Playwright MCP gateway (the docker compose service declared
# in this module's docker-compose.yml) to the desired state and waits for it to
# accept MCP requests, so the harness that starts right after `devbot up` finds
# it ready.
#
# Runs on `devbot up` — after docker services are started. The project directory
# is passed as $1 by bin/up.sh; falls back to cwd (unused here).
#
# Non-fatal by contract (the boot continues without the browser), but a failed
# reconciliation returns non-zero so bin/up.sh withholds the start stamp: a
# container that still answers the probe while holding an old configuration must
# not be recorded as a completed start.
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "${MODULE_DIR}/../../.." && pwd)}"
export DEV_BOT_ROOT

# This module ships no functions.sh — source the shared library directly, as
# bin/down.sh does.
# shellcheck source=../../_shared/functions.sh
source "${DEV_BOT_ROOT}/src/_shared/functions.sh"

PLAYWRIGHT_MCP_URL="${PLAYWRIGHT_MCP_URL:-http://127.0.0.1:18505/mcp}"
CONTAINER_NAME="dev-bot-playwright-mcp"
SERVICE_NAME="playwright-mcp"
COMPOSE_FILE="${MODULE_DIR}/docker-compose.yml"
FINGERPRINT_FILE="${DEV_BOT_ROOT}/storage/playwright/.compose-fingerprint"

# ── What the container must have been created from ────────────────────────────
# A hash of the compose file plus the mount root. Docker fixes EVERY creation-time
# property (mount, image, working directory, command, healthcheck) and devbot up
# runs compose with --no-recreate, so nothing else would ever apply an edit. A
# file hash catches all of them at once; comparing individual `docker inspect`
# fields misses the next property someone adds.
_desired_fingerprint() {
  [[ -r "${COMPOSE_FILE}" ]] || return 1
  python3 - "${COMPOSE_FILE}" "${PLAYWRIGHT_ROOT:-}" <<'PY'
import hashlib, sys

digest = hashlib.sha256()
with open(sys.argv[1], "rb") as fh:
    digest.update(fh.read())
digest.update(b"\0" + sys.argv[2].encode())
print(digest.hexdigest())
PY
}

# ── Was the container created before the file changed? ────────────────────────
# Exit 0 when the container predates the compose file (so it may hold an older
# configuration), 1 when it is newer (created by this run, or by compose moments
# ago). An unreadable timestamp counts as predating: recreate rather than adopt.
_container_predates_file() {
  local cid="$1" created
  created="$(docker inspect "${cid}" --format '{{.Created}}' 2>/dev/null || true)"
  [[ -n "${created}" ]] || return 0
  python3 - "${created}" "${COMPOSE_FILE}" <<'PY'
import datetime, os, re, sys

raw = sys.argv[1]
# Docker reports RFC3339 with nanoseconds; fromisoformat wants microseconds.
raw = re.sub(r"\.(\d+)", lambda m: "." + (m.group(1) + "000000")[:6], raw).replace("Z", "+00:00")
try:
    created = datetime.datetime.fromisoformat(raw).timestamp()
except ValueError:
    sys.exit(0)
sys.exit(0 if created < os.path.getmtime(sys.argv[2]) else 1)
PY
}

_record_fingerprint() {
  mkdir -p "$(dirname "${FINGERPRINT_FILE}")" 2>/dev/null || true
  printf '%s\n' "$1" > "${FINGERPRINT_FILE}" 2>/dev/null || true
}

# ── Reconcile the container against the file it was created from ──────────────
_reconcile_service_state() {
  local cid desired recorded
  cid="$(docker ps -aq --filter "name=^${CONTAINER_NAME}$" 2>/dev/null | head -1 || true)"
  # Not created yet: the compose call in bin/up.sh already used the right file.
  [[ -z "${cid}" ]] && return 0

  if ! desired="$(_desired_fingerprint)"; then
    _warn "playwright — cannot read ${COMPOSE_FILE} — gateway not reconciled"
    return 0
  fi
  recorded="$(cat "${FINGERPRINT_FILE}" 2>/dev/null || true)"

  if [[ -n "${recorded}" && "${recorded}" == "${desired}" ]]; then
    return 0
  fi

  if [[ -z "${recorded}" ]] && ! _container_predates_file "${cid}"; then
    # Created from the file now in force (this up run, or compose a moment ago):
    # record it instead of recreating a healthy container on every clean start.
    _record_fingerprint "${desired}"
    return 0
  fi

  # Either the file changed, or the container predates this check (an older
  # release): recreate once so the configuration in force is the one it runs.
  _warn "playwright — gateway does not match ${COMPOSE_FILE##*/} — recreating"
  if ! docker compose -f "${COMPOSE_FILE}" up -d --force-recreate "${SERVICE_NAME}"; then
    # A stale gateway that still answers the readiness probe must not be
    # reported as reconciled: non-zero withholds the start stamp, so the next
    # start retries instead of trusting this one.
    _warn "playwright — could not recreate the gateway; the running container still holds the old configuration"
    return 1
  fi

  _record_fingerprint "${desired}"
  _ok "playwright — gateway recreated from the current ${COMPOSE_FILE##*/}"
  return 0
}

main() {
  _info "playwright — up"

  # The compose file interpolates PLAYWRIGHT_ROOT as mandatory, so the root must
  # be exported on this path too.
  if ! _devbot_export_playwright_root; then
    _warn "playwright — PLAYWRIGHT_ROOT is not a usable path — gateway not reconciled"
    return 0
  fi

  if ! _reconcile_service_state; then
    return 1
  fi

  # An `if`, not `&&`: under `set -e` a short-circuited `&&` would abort here.
  if _devbot_wait_for_mcp_gateway playwright "${PLAYWRIGHT_MCP_URL}"; then
    _ok "playwright gateway reachable at ${PLAYWRIGHT_MCP_URL}"
  fi

  return 0
}

main "$@"
