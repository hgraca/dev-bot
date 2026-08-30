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
  _header_2 "Docker Services"

  if [[ ! -f "${DEV_BOT_ROOT}/.devbot.global.jsonc" ]]; then
    _fatal "No .devbot.global.jsonc found at ${DEV_BOT_ROOT}/.devbot.global.jsonc — run 'make install' first."
    exit 1
  fi

  _header_3 "Stopping docker services..."

  # ── Discover docker-compose.yml files in tool modules ──────────────────
  local compose_files=()
  while IFS= read -r -d '' f; do
    compose_files+=("${f}")
  done < <(find "${DEV_BOT_ROOT}/src/tools" -maxdepth 2 -name 'docker-compose.yml' -type f -print0 2>/dev/null)

  # ── Resolve disabled modules ────────────────────────────────────────────
  local disabled_modules_list
  disabled_modules_list=$(_devbot_get_disabled_modules)
  local disabled_lines
  disabled_lines=$(echo "${disabled_modules_list}" | python3 -c "
import json, sys
for m in json.loads(sys.stdin.read()):
    print(m)
" 2>/dev/null || true)

  # ── Build compose file list, filtering disabled tools ────────────────────
  local compose_opts=()
  if [[ -f "${DEV_BOT_ROOT}/docker-compose.yml" ]]; then
    compose_opts=("-f" "docker-compose.yml")
  fi
  local gpu_eligible=false

  for f in "${compose_files[@]}"; do
    local tool_dir="$(dirname "${f}")"
    local tool="$(basename "${tool_dir}")"    # e.g. "ollama", "litellm"

    if echo "${disabled_lines}" | grep -Fxq "${tool}" 2>/dev/null; then
      _skip "${tool}: disabled per config — skipping ${tool_dir}/docker-compose.yml"
      continue
    fi

    # Use path relative to DEV_BOT_ROOT so docker compose resolves correctly
    local rel="${f#${DEV_BOT_ROOT}/}"
    compose_opts+=("-f" "${rel}")
  done

  # ── GPU eligibility: true only if at least one non-gpu tool compose was added ──
  if [[ ${#compose_opts[@]} -gt 0 ]]; then
    gpu_eligible=true
  fi

  if [[ "${gpu_eligible}" == true ]] && _devbot_is_true "gpu_enabled"; then
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
