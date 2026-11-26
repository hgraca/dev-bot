#!/usr/bin/env bash
# =============================================================================
# bin/down.sh
# Removes all containers in the `devbot` compose project, plus any a module's
# down.sh reaps (datasources' sidecars, started from a compose file generated
# under storage/). Containers stranded under a DIFFERENT compose project — the
# retired `dev-bot` name, or a bare `docker run` — are not reached here:
# bin/up.sh's stale-name reclaim owns those.
#
# Lifetime is install-level, not project-level: every module's services live in
# ONE compose project (`devbot`), shared by every harness session on this
# machine. So removal is machine-wide — never "this project's services". mdctx
# and codebase-memory serve every project, and stopping "this project's" copy
# would stop another live session's.
#
# Invariant (see the registry notes in src/_shared/functions.sh):
#   remove dev-bot containers  ⟺  no live devbot session
#                                  AND no live registered container owner
#   either one live  ⟹  nothing is removed. `bin/up.sh` may ADD containers but
#               never removes one belonging to project `devbot` (it does reclaim
#               containers stranded under other project names, and force-
#               recreates ollama to reconcile its GPU state).
#
# A "container owner" is a caller that is not a devbot session and keeps the
# stack alive on its own — herdr today: it runs `devbot up --owner herdr` and
# opens its panes itself, so a devbot session opened inside herdr must not tear
# the stack down on exit. `devbot down --owner <name>` is how that owner ends
# its claim; the gate then removes the containers only if nothing else — session
# or owner — remains.
#
# The same removal must not overlap a start: up.sh holds the install-level up
# lock for its whole sequence, so down takes it BEFORE the registry gate (that
# order is what keeps the pair acyclic) and refuses rather than tear the stack
# down mid-up. A last-session teardown takes it without waiting — it already
# holds the registry lock, and waiting there would invert that order.
# Containers a refused teardown leaves behind are reclaimed by the next start
# or an explicit `down`.
#
# The last session to exit reaches the count-0 path via
# _devbot_session_teardown; an explicit `devbot down` while a session or an
# owner is live is a no-op that warns. There is no override flag: the containers
# are shared, and removing them under a live session or owner is the bug the gate
# exists to prevent.
#
# Usage:
#   bin/down.sh [--owner <name> [--owner-pid <pid>]] [project-dir]
#
# [project-dir] does NOT scope the teardown — removal is always machine-wide.
# It is only forwarded to each module's down.sh (none currently reads it).
#
# --owner names a registered container owner giving its claim up (the pid
# defaults to the invoking process, the same default `devbot up --owner` uses).
# The claim is released inside the gate's critical section, and the teardown
# then happens only if neither a session nor another owner is left.
# =============================================================================

set -euo pipefail

DEV_BOT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEV_BOT_ROOT

# ── Source shared library ──────────────────────────────────────────────────────
# shellcheck source=../src/_shared/functions.sh
source "${DEV_BOT_ROOT}/src/_shared/functions.sh"

# ── Arguments ──────────────────────────────────────────────────────────────────
DOWN_OWNER=""
DOWN_OWNER_PID=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner)
      [[ -n "${2:-}" ]] || { _fatal "--owner needs a name"; exit 1; }
      DOWN_OWNER="$2"
      shift 2
      ;;
    --owner-pid)
      [[ -n "${2:-}" ]] || { _fatal "--owner-pid needs a pid"; exit 1; }
      DOWN_OWNER_PID="$2"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -*)
      _fatal "unknown option: $1"
      exit 1
      ;;
    *)
      break
      ;;
  esac
done
# Validated here, where a typo is still the caller's error to see: a name that
# cannot be a claim file would otherwise silently release nothing.
if [[ -z "${DOWN_OWNER}" && -n "${DOWN_OWNER_PID}" ]]; then
  _fatal "--owner-pid names the process of an owner — pass --owner too"
  exit 1
fi
if [[ -n "${DOWN_OWNER}" ]]; then
  _devbot_owner_name_ok "${DOWN_OWNER}" || { _fatal "invalid owner name '${DOWN_OWNER}'"; exit 1; }
  DOWN_OWNER_PID="${DOWN_OWNER_PID:-$PPID}"
  # A canonical positive pid only: 0 is a process group, 007 names nothing.
  [[ "${DOWN_OWNER_PID}" =~ ^[1-9][0-9]*$ ]] \
    || { _fatal "invalid owner pid '${DOWN_OWNER_PID}'"; exit 1; }
fi

PROJECT_DIR="$(cd "${1:-$(pwd)}" && pwd 2>/dev/null || true)"

# ── Lifetime gate ──────────────────────────────────────────────────────────────
# Gates the WHOLE teardown, module down-scripts included: a module's reaper
# removes containers that belong to whichever instance is using them (a module
# disabled in this project may own a container another project is using), and
# the compose set itself is machine-wide. Removing anything before the last exit
# would break a live session.
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

  # An owner ending its own claim does it INSIDE the critical section, so the
  # probe below cannot see the claim this `down` is retiring and abort on it.
  # The release never takes a lock (this guard holds it) and never touches
  # fd 200, so the lock stays held across the probe and the removal.
  if [[ -n "${DOWN_OWNER}" ]]; then
    _devbot_owner_release "${DOWN_OWNER}" "${DOWN_OWNER_PID}"
  fi

  local live
  live="$(_devbot_live_session_count --prune)"
  if [[ "${live}" -gt 0 ]]; then
    _warn "${live} devbot instance(s) still running — containers kept"
    _down_release_lock
    return 1
  fi

  # Sessions are the implicit owners of a stack they started; these are the
  # registered ones (herdr, and whatever comes next). A claim outlives every
  # session by design, so a `down` that is not that owner's leaves the stack.
  local owners
  owners="$(_devbot_live_owner_names --prune | paste -sd, -)"
  if [[ -n "${owners}" ]]; then
    _warn "container owner '${owners}' still registered — containers kept"
    _down_release_lock
    return 1
  fi
  return 0
}

# Release the registry lock, but only if WE took it — never yank the caller's.
# The up lock (fd 201) is always ours when it is open.
_down_release_lock() {
  if ! _down_lock_held; then
    { exec 200>&-; } 2>/dev/null || true
  fi
  { exec 201>&-; } 2>/dev/null || true
}

# ── Up lock ────────────────────────────────────────────────────────────────────
# A start holds the install-level up lock for its whole sequence, and its module
# scripts may take the registry lock from under it — so removal takes the up
# lock BEFORE the registry gate, never after. Taken on fd 201: fd 200 carries
# the registry lock.
_down_wait_for_up() {
  local path
  path="$(_devbot_up_lock_path)"
  mkdir -p "$(dirname "${path}")" 2>/dev/null || true
  if ! { exec 201>"${path}"; } 2>/dev/null; then
    _warn "could not open ${path} — tearing down without waiting for a start"
    return 0
  fi
  # The caller of a last-session teardown already holds the registry lock, and
  # waiting here would invert the order above. Its gate already proved no
  # session is live; a start it could still race is an explicit `devbot up`, so
  # take the lock without waiting and leave the stack to it on refusal.
  if _down_lock_held; then
    _devbot_lock_acquire 201 0 \
      "a start is in progress — leaving the containers to it"
    return $?
  fi
  _devbot_lock_acquire 201 "${DEVBOT_DOWN_UP_LOCK_WAIT:-30}" \
    "a start is in progress (up lock held >${DEVBOT_DOWN_UP_LOCK_WAIT:-30}s) — refusing to tear the stack down"
}

# ── Module down scripts ────────────────────────────────────────────────────────
# EVERY module's down.sh runs, including disabled ones (--all): a module
# disabled in this project may still own a container the compose set does not
# declare — datasources starts sidecars from a generated compose under storage/.
# Covered by the disabled-module regression test.

_run_down_scripts() {
  _header_2 "Down Scripts"
  # The registry lock is held here — _down_guard returns 0 only after taking it
  # — so module down scripts must not block on their own lifecycle locks: up.sh
  # holds the datasources lifecycle lock and then waits for the registry lock,
  # and waiting the other way round here would deadlock the two. The flag tells
  # them to take it non-blocking.
  _DEVBOT_REGISTRY_LOCK_HELD=1 _run_service_scripts --all "down.sh" "${PROJECT_DIR}"
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
  # compose interpolates the gateway mount roots as mandatory, so a set that
  # includes them aborts on an unresolved one and stops nothing. `down` never
  # reads the mount, only the interpolation, so any absolute value will do: a
  # typo'd root must not leave the user unable to tear down what a failed up
  # just started.
  if ! _devbot_export_playwright_root; then
    _warn "PLAYWRIGHT_ROOT is not a usable path — using \$HOME for interpolation; down does not read the mount"
    export PLAYWRIGHT_ROOT="${HOME:-/}"
  fi
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

  # Up lock FIRST, then the registry gate. Taking them in that order — the order
  # a start uses — is what keeps the pair acyclic. Both are held until
  # _down_release_lock below.
  if ! _down_wait_for_up; then
    _down_release_lock
    return 1
  fi

  # Holds the registry lock too until the same release — the whole teardown
  # (module down-scripts included) stays inside the critical section.
  _down_guard || {
    _down_release_lock
    return 0
  }

  _run_down_scripts
  _docker_down

  _down_release_lock

  echo -e "  ${TEXT_DIM}⏱  Total: $(_fmt_duration $(( SECONDS - total_start )))${TEXT_CLEAR}"
  echo
}

main "$@"
