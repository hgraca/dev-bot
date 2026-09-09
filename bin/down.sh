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
  # Mirror bin/up.sh discovery: docker services are only ever started for
  # enabled modules (consumer fragments may `include:` a disabled provider's
  # compose). Same scan + disabled filter; skip silently when nothing is
  # enabled — there is nothing to stop.
  local disabled_modules_list
  disabled_modules_list=$(_devbot_get_disabled_modules)
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
  local compose_opts=()
  if [[ -f "${DEV_BOT_ROOT}/docker-compose.yml" ]]; then
    compose_opts=("-f" "docker-compose.yml")
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
  done

  if [[ ${#compose_opts[@]} -eq 0 ]]; then
    _skip "no docker services needed by enabled modules"
    return 0
  fi

  _header_2 "Docker Services"

  if [[ ! -f "${DEV_BOT_ROOT}/.devbot.global.jsonc" ]]; then
    _fatal "No .devbot.global.jsonc found at ${DEV_BOT_ROOT}/.devbot.global.jsonc — run 'make install' first."
    exit 1
  fi

  _header_3 "Stopping docker services..."

  # ── GPU override: append docker-compose.gpu.yml when enabled ─────────────
  if _devbot_is_true "gpu_enabled"; then
    compose_opts+=("-f" "docker-compose.gpu.yml")
  fi

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
