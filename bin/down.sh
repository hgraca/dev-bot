#!/usr/bin/env bash
# =============================================================================
# bin/down.sh
# Tears down docker compose services for dev-bot.
#
# Usage:
#   bin/down.sh
# =============================================================================

set -euo pipefail

DEV_BOT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEV_BOT_ROOT

# ── Source shared library ──────────────────────────────────────────────────────
# shellcheck source=../src/_shared/functions.sh
source "${DEV_BOT_ROOT}/src/_shared/functions.sh"

PROJECT_DIR="$(cd "${1:-$(pwd)}" && pwd 2>/dev/null || true)"

# ── Module down scripts ────────────────────────────────────────────────────────

_run_down_scripts() {
  _header_2 "Down Scripts"
  _run_service_scripts "down.sh" "${PROJECT_DIR}"
}

# ── Docker services ────────────────────────────────────────────────────────────

_docker_down() {
  # dev-bot must be installed (global config) — report before doing anything,
  # regardless of whether any compose files are discovered.
  if [[ ! -f "${DEV_BOT_ROOT}/.devbot.global.jsonc" ]]; then
    _fatal "No .devbot.global.jsonc found at ${DEV_BOT_ROOT}/.devbot.global.jsonc — run 'make install' first."
    exit 1
  fi

  # Mirror bin/up.sh discovery: docker services are only ever started for
  # enabled modules (consumer fragments may `include:` a disabled provider's
  # compose). Same scan + disabled filter; skip silently when nothing is
  # enabled — there is nothing to stop.
  # Pass the project dir, mirroring bin/up.sh: the effective set is
  # global ∘ per-project, so omitting it would read the global map alone and
  # miss the compose of a module this project enables.
  local disabled_modules_list
  disabled_modules_list=$(_devbot_get_disabled_modules "${PROJECT_DIR}")
  local disabled_lines
  disabled_lines=$(echo "${disabled_modules_list}" | python3 -c "
import json, sys
for m in json.loads(sys.stdin.read()):
    print(m)
" 2>/dev/null || true)

  local compose_files=()
  local base_dir
  for base_dir in "${DEV_BOT_ROOT}/src/tools" "${DEV_BOT_ROOT}/src/agentic" "${DEV_BOT_ROOT}/src/harnesses"; do
    [[ -d "${base_dir}" ]] || continue
    while IFS= read -r -d '' f; do
      compose_files+=("${f}")
    done < <(find "${base_dir}" -maxdepth 2 -name 'docker-compose.yml' -type f -print0 2>/dev/null)
  done

  # ── Build compose file list, filtering disabled modules ──────────────────
  # Mirrors bin/up.sh: a module's docker-compose.gpu.yml is included only when
  # GPU passthrough is available AND that module's compose is selected.
  local gpu_ok=0
  if _devbot_is_true "gpu_enabled" && _has_docker_gpu; then
    gpu_ok=1
  fi

  local compose_opts=()
  # Kept in step with bin/up.sh: a consumer that ships a root docker-compose.yml
  # gets it first (compose reads the project `name:` from the first -f file),
  # plus its GPU overlay. dev-bot ships no root compose, so this is normally
  # skipped; down must still select the same set up did when one exists.
  if [[ -f "${DEV_BOT_ROOT}/docker-compose.yml" ]]; then
    compose_opts=("-f" "docker-compose.yml")
    if [[ ${gpu_ok} -eq 1 && -f "${DEV_BOT_ROOT}/docker-compose.gpu.yml" ]]; then
      compose_opts+=("-f" "docker-compose.gpu.yml")
    fi
  fi

  for f in "${compose_files[@]}"; do
    local mod_dir mod_name
    mod_dir="$(dirname "${f}")"
    mod_name="$(basename "${mod_dir}")"    # e.g. "ollama", "codebase-index"

    if echo "${disabled_lines}" | grep -Fxq "${mod_name}" 2>/dev/null; then
      _skip "${mod_name}: disabled per config — skipping ${mod_dir}/docker-compose.yml"
      continue
    fi

    # Use path relative to DEV_BOT_ROOT so docker compose resolves correctly
    local rel="${f#${DEV_BOT_ROOT}/}"
    compose_opts+=("-f" "${rel}")

    # The module's GPU overlay, if it ships one, follows its compose. Kept in
    # step with bin/up.sh: an overlay may declare
    # `devbot:gpu-overlay-skip-if-included <compose>` and is then skipped when
    # that compose is already in the set, so a consumer fragment and its
    # provider never both apply the same device reservation.
    local gpu_rel="${rel%docker-compose.yml}docker-compose.gpu.yml"
    if [[ ${gpu_ok} -eq 1 && -f "${DEV_BOT_ROOT}/${gpu_rel}" ]]; then
      local skip_if
      skip_if="$(_gpu_overlay_skip_if "${DEV_BOT_ROOT}/${gpu_rel}")"
      if [[ -n "${skip_if}" ]] && printf '%s\n' "${compose_opts[@]}" | grep -Fxq "${skip_if}"; then
        _skip "${mod_name}: GPU overlay skipped — ${skip_if} already applies it"
      else
        compose_opts+=("-f" "${gpu_rel}")
      fi
    fi
  done

  if [[ ${#compose_opts[@]} -eq 0 ]]; then
    _skip "no docker services needed by enabled modules"
    return 0
  fi

  _header_2 "Docker Services"

  # Inside a container there is no docker daemon — the containers run on the
  # host, so they cannot be stopped from here. Skip instead of failing
  # `docker compose down` (mirrors bin/up.sh's guard).
  if ! docker info >/dev/null 2>&1; then
    _skip "no docker daemon (inside a container?) — docker services not stopped here; stop them on the host"
    return 0
  fi

  _header_3 "Stopping docker services..."

  cd "${DEV_BOT_ROOT}"
  _log "docker compose ${compose_opts[*]} down --remove-orphans"
  docker compose "${compose_opts[@]}" down --remove-orphans
  _ok "Docker services stopped"
}

# ── main ───────────────────────────────────────────────────────────────────────
main() {
  local total_start=${SECONDS}

  _header_1 "DevBot Down"

  _run_down_scripts
  _docker_down

  echo -e "  ${TEXT_DIM}⏱  Total: $(_fmt_duration $(( SECONDS - total_start )))${TEXT_CLEAR}"
  echo
}

main "$@"
