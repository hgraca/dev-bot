#!/usr/bin/env bash
# =============================================================================
# bin/down.sh
# Removes all containers in the `devbot` compose project, plus the non-compose
# ones a module's down.sh reaps (playwright's labelled `docker run` containers).
# Containers stranded under a DIFFERENT compose project — the retired `dev-bot`
# name, or a bare `docker run` — are not reached here: bin/up.sh's stale-name
# reclaim owns those.
#
# Lifetime is install-level, not project-level: every module's services live in
# ONE compose project (`devbot`), shared by every harness session on this
# machine. So removal is machine-wide — never "this project's services". mdctx
# and codebase-memory serve every project, and stopping "this project's" copy
# would stop another live session's.
#
# Invariant (see the registry note in src/_shared/functions.sh):
#   remove dev-bot containers  ⟺  live devbot session count == 0
#   live > 0  ⟹  nothing is removed. `bin/up.sh` may ADD containers but never
#               removes one belonging to project `devbot` (it does reclaim
#               containers stranded under other project names, and force-
#               recreates ollama to reconcile its GPU state).
#
# The last session to exit reaches the count-0 path via
# _devbot_session_teardown; an explicit `devbot down` while instances are alive
# is a no-op that warns.
#
# Usage:
#   bin/down.sh [project-dir]
#
# [project-dir] does NOT scope the teardown — removal is always machine-wide.
# It is only forwarded to each module's down.sh (none currently reads it).
# =============================================================================

set -euo pipefail

DEV_BOT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEV_BOT_ROOT

# ── Source shared library ──────────────────────────────────────────────────────
# shellcheck source=../src/_shared/functions.sh
source "${DEV_BOT_ROOT}/src/_shared/functions.sh"

PROJECT_DIR="$(cd "${1:-$(pwd)}" && pwd 2>/dev/null || true)"

# ── Lifetime gate ──────────────────────────────────────────────────────────────
# Gates the WHOLE teardown, module down-scripts included: playwright's reaper
# removes this machine's playwright containers, and those belong to whichever
# instance is using them (playwright is per-instance, not shared). Removing
# anything before the last exit would break a live session.
#
# The gate takes the registry lock and HOLDS it for the whole removal, so the
# session count cannot change between the probe and the containers going away.
# A session registering concurrently either publishes its file before our probe
# (count >= 1 → we abort) or blocks on the lock until we are done (its
# containers then start after our removal — harmless). Probing without the lock
# would be check-then-act: a session could register in the window and have its
# containers removed underneath it.
#
# No escape hatch by design (user decision, 2026-09-22): a project-scoped
# override cannot be safe while the containers are machine-wide.
#
# _devbot_session_teardown calls us from inside its own critical section and
# sets _DEVBOT_REGISTRY_LOCK_HELD; re-locking the same directory from a second
# process would block forever, so honour the flag and never re-lock.
_down_lock_held() { [[ "${_DEVBOT_REGISTRY_LOCK_HELD:-0}" == "1" ]]; }

_down_guard() {
  local dir
  dir="$(_devbot_sessions_dir)"

  if ! _down_lock_held; then
    mkdir -p "${dir}" 2>/dev/null || true
    if ! _devbot_lock_wait "${dir}" 30 \
      "session registry lock held >30s by another process — skipping teardown"; then
      return 1
    fi
  fi

  local live
  live="$(_devbot_live_session_count)"
  if [[ "${live}" -gt 0 ]]; then
    _warn "${live} devbot instance(s) still running — containers kept"
    _down_release_lock
    return 1
  fi
  return 0
}

# Release the registry lock, but only if WE took it — never yank the caller's.
_down_release_lock() {
  _down_lock_held && return 0
  exec 200>&- 2>/dev/null || true
}

# ── Module down scripts ────────────────────────────────────────────────────────
# EVERY module's down.sh runs, including disabled ones (--all): a module
# disabled in this project may still own a NON-compose container — playwright
# reaps its own by label, and `docker compose down` cannot collect those.
# Covered by the disabled-module regression test.

_run_down_scripts() {
  _header_2 "Down Scripts"
  _run_service_scripts --all "down.sh" "${PROJECT_DIR}"
}

# ── Docker services ────────────────────────────────────────────────────────────

_docker_down() {
  # dev-bot must be installed (global config) — report before doing anything,
  # regardless of whether any compose files are discovered.
  if [[ ! -f "${DEV_BOT_ROOT}/.devbot.global.jsonc" ]]; then
    _fatal "No .devbot.global.jsonc found at ${DEV_BOT_ROOT}/.devbot.global.jsonc — run 'make install' first."
    exit 1
  fi

  # ── Discover EVERY module compose ────────────────────────────────────────
  # No disabled-module filter and no project argument: the disabled set is a
  # per-project view, but removal is machine-wide — a module disabled HERE may
  # still own a container (signoz enabled elsewhere). Config-independent, so a
  # project that enables no docker modules still tears the machine down (the
  # old project-scoped set early-returned and removed nothing).
  local compose_opts=()
  local base_dir f
  for base_dir in "${DEV_BOT_ROOT}/src/tools" "${DEV_BOT_ROOT}/src/agentic" "${DEV_BOT_ROOT}/src/harnesses"; do
    [[ -d "${base_dir}" ]] || continue
    while IFS= read -r -d '' f; do
      # Path relative to DEV_BOT_ROOT so docker compose resolves correctly.
      compose_opts+=("-f" "${f#${DEV_BOT_ROOT}/}")
    done < <(find "${base_dir}" -maxdepth 2 -name 'docker-compose.yml' -type f -print0 2>/dev/null)
  done

  # A consumer's own root compose is a member of the same project and belongs in
  # the set (compose reads the project `name:` from the first -f file). No GPU
  # overlays: `down` needs no device reservations, so the up.sh overlay logic
  # has no counterpart here.
  if [[ -f "${DEV_BOT_ROOT}/docker-compose.yml" ]]; then
    compose_opts=("-f" "docker-compose.yml" "${compose_opts[@]}")
  fi

  if [[ ${#compose_opts[@]} -eq 0 ]]; then
    _skip "no docker services to stop"
    return 0
  fi

  _header_2 "Docker Services"

  # Inside a container there is no docker daemon — the containers run on the
  # host, so they cannot be stopped from here. Skip instead of failing
  # `docker compose down`.
  if ! docker info >/dev/null 2>&1; then
    _skip "no docker daemon (inside a container?) — docker services not stopped here; stop them on the host"
    return 0
  fi

  _header_3 "Stopping docker services..."

  cd "${DEV_BOT_ROOT}"
  # --remove-orphans collects the containers no selected compose declares —
  # including datasources, whose generated compose lives under storage/ and is
  # outside the discovery path.
  _log "docker compose ${compose_opts[*]} down --remove-orphans"
  docker compose "${compose_opts[@]}" down --remove-orphans
  _ok "Docker services stopped"
}

# ── main ───────────────────────────────────────────────────────────────────────

main() {
  local total_start=${SECONDS}

  _header_1 "DevBot Down"

  # Holds the registry lock until _down_release_lock below — the whole teardown
  # (module down-scripts included) stays inside the critical section.
  _down_guard || return 0

  _run_down_scripts
  _docker_down

  _down_release_lock

  echo -e "  ${TEXT_DIM}⏱  Total: $(_fmt_duration $(( SECONDS - total_start )))${TEXT_CLEAR}"
  echo
}

main "$@"
