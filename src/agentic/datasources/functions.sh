#!/usr/bin/env bash
# src/agentic/datasources/functions.sh
# Thin wrapper: sources the root shared library, plus the module's helpers that
# both up.sh and reconcile.sh need.
set -euo pipefail
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export MODULE_DIR
source "${MODULE_DIR}/../../_shared/functions.sh"

# ── Sidecar reconcile ────────────────────────────────────────────────────────
#
# A sidecar is rendered from the static project set but RUNS only while a live
# session wants it. up.sh applies this on boot; reconcile.sh applies it on a
# session's exit. Both converge to the same answer, derived from the live session
# registry, so they are last-writer-safe rather than lock-ordered.

# _running_sidecars — the sidecar names currently RUNNING. Read from docker
#   rather than from the rendered compose: a leftover started before a config
#   change may no longer be a compose service, and the reconcile must reclaim it
#   too. The gateway's own container is excluded — its name is not a datasource.
_running_sidecars() {
  docker ps --filter 'name=dev-bot-datasources-' --format '{{.Names}}' 2>/dev/null |
    sed 's/^dev-bot-datasources-//' | grep -vx 'mcp' || true
}

# _wanted_sidecars <project-dir>... — the sidecars those projects demand,
#   space-joined. A project with no config, or one that opted into no sidecar,
#   contributes nothing.
#
#   A FAILED catalogue read is not an empty catalogue: returning empty demand for
#   it would read as "stop everything" and take down sidecars live sessions are
#   using. It returns non-zero instead, and the caller leaves the running set
#   untouched — the discipline render.sh follows for the same reason.
_wanted_sidecars() {
  local catalogue
  if ! catalogue="$(python3 "${MODULE_DIR}/../../_shared/read_jsonc.py" \
    "${DEV_BOT_ROOT}/.devbot.global.jsonc" datasources 2>/dev/null)"; then
    return 1
  fi
  [[ -n "${catalogue}" ]] || catalogue="{}"
  printf '%s' "${catalogue}" | python3 "${MODULE_DIR}/demand.py" \
    --projects-names "$@" 2>/dev/null
}

# _datasources_declared_count — the number of datasources declared in the global
#   catalogue. A fresh install ships an empty catalogue, so install.sh uses this
#   to skip the toolbox image pull (which would otherwise only warn) — audit-80
#   N8. A failed config read returns non-zero so the caller errs toward pulling.
_datasources_declared_count() {
  local catalogue
  catalogue="$(python3 "${MODULE_DIR}/../../_shared/read_jsonc.py" \
    "${DEV_BOT_ROOT}/.devbot.global.jsonc" datasources 2>/dev/null)" || return 1
  [[ -n "${catalogue}" && "${catalogue}" != "null" ]] || {
    printf '0'
    return 0
  }
  printf '%s' "${catalogue}" |
    python3 -c 'import json, sys; print(len(json.load(sys.stdin)))' 2>/dev/null || return 1
}

# _reconcile_sidecars <wanted> — stop every running sidecar not in <wanted>.
_reconcile_sidecars() {
  local wanted="$1" svc
  for svc in $(_running_sidecars); do
    if ! printf ' %s ' "${wanted}" | grep -Fq " ${svc} "; then
      if docker stop "dev-bot-datasources-${svc}" >/dev/null 2>&1; then
        _ok "datasources — sidecar '${svc}' stopped (no live session wants it)"
      else
        _warn "datasources — could not stop sidecar '${svc}'"
      fi
    fi
  done
}
