#!/usr/bin/env bash
# =============================================================================
# bin/up.sh
# Runs all up.sh scripts discovered under src/. Intended to be called after
# docker services are up (e.g., pull models, wait for dependencies).
#
# Usage:
#   bin/up.sh                    # run in current directory
#   bin/up.sh /path/to/project   # run in specified project
#
# Adding a new up step:
#   Create src/tools/<module>/up.sh or src/agentic/<module>/up.sh — it will be auto-discovered and run.
# =============================================================================

set -euo pipefail

DEV_BOT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEV_BOT_ROOT

# ── Source shared library ──────────────────────────────────────────────────────
# shellcheck source=../src/_shared/functions.sh
source "${DEV_BOT_ROOT}/src/_shared/functions.sh"

PROJECT_DIR="$(cd "${1:-$(pwd)}" && pwd 2>/dev/null || true)"

if [[ -z "${PROJECT_DIR}" || ! -d "${PROJECT_DIR}" ]]; then
  _fatal "Directory '${1:-.}' does not exist or cannot be resolved."
  exit 1
fi

_run_up_scripts() {
  _header_2 "Up Scripts"
  _run_service_scripts "up.sh" "${PROJECT_DIR}"
}

# ── External module config (rebuild from internal module declarations) ──────────

_rebuild_external_module_config() {
  _header_2 "External Module Config"

  local config_file="${DEV_BOT_ROOT}/.devbot.global.jsonc"
  if [[ ! -f "${config_file}" ]]; then
    _error "No .devbot.global.jsonc found at ${config_file} — run 'make install' first."
    return 1
  fi

  # ── Resolve disabled modules ──────────────────────────────────────────────
  local disabled_raw
  disabled_raw=$(_devbot_get_disabled_modules)
  local disabled_modules
  disabled_modules=$(echo "${disabled_raw}" | python3 -c "
import json, sys
for m in json.loads(sys.stdin.read()):
    print(m)
" 2>/dev/null || true)

  local merge_script="${DEV_BOT_ROOT}/src/_shared/merge_modules_jsonc.py"
  local found_count=0
  local added_count=0

  # ── Scan enabled modules for external-modules.json ────────────────────────
  for module_dir in "${DEV_BOT_ROOT}/src/agentic/"*/ "${DEV_BOT_ROOT}/src/tools/"*/; do
    local module_name
    module_name="$(basename "${module_dir}")"

    if echo "${disabled_modules}" | grep -Fxq "${module_name}" 2>/dev/null; then
      continue
    fi

    local ext_file="${module_dir}/external-modules.json"
    if [[ ! -f "${ext_file}" ]]; then
      continue
    fi

    found_count=$((found_count + 1))

    local result
    result=$(python3 "${merge_script}" "${config_file}" "${ext_file}" 2>&1) || true

    if echo "${result}" | grep -q "^INSERTED"; then
      _log "${module_name}: ${result}"
      added_count=$((added_count + 1))
    else
      _skip "${module_name}: ${result}"
    fi
  done

  if [[ ${found_count} -eq 0 ]]; then
    _info "No external-modules.json declarations found in enabled modules"
  else
    _ok "${found_count} module(s) with external module declarations processed (${added_count} with new entries added)"
  fi

  # Format .devbot.global.jsonc to ensure consistent JSON formatting after merge
  local format_json_tool="${DEV_BOT_ROOT}/src/agentic/format-json/tools/format-json.mcp.sh"
  if [[ -f "${format_json_tool}" ]]; then
    bash "${format_json_tool}" "${config_file}" 2>/dev/null || true
  fi
}

# ── Docker services ────────────────────────────────────────────────────────────

_docker_up() {
  # ── Discover docker-compose.yml files across every module base dir ─────
  # (tools + agentic + harnesses). Since v1.4 docker services start only when
  # an ENABLED module needs them: a module disabled in the `modules` map has
  # its compose excluded, and a consumer module that needs a provider's
  # service ships its own fragment that `include:`s the provider compose (so
  # the provider boots even when its own module is disabled). If NO enabled
  # module ships a compose file, docker has nothing to start — skip the whole
  # section silently (no header, no `docker compose` invocation).
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

  # Inside a container there is no docker daemon — the host runs the docker
  # services (reachable from here via --network host). Skip instead of
  # failing `docker compose up`.
  if ! docker info >/dev/null 2>&1; then
    _skip "no docker daemon (inside a container?) — docker services not started here; run them on the host"
    return 0
  fi

  if [[ ! -f "${DEV_BOT_ROOT}/.devbot.global.jsonc" ]]; then
    _fatal "No .devbot.global.jsonc found at ${DEV_BOT_ROOT}/.devbot.global.jsonc — run 'make install' first."
    exit 1
  fi

  _header_3 "Starting docker services..."

  # ── GPU override: append docker-compose.gpu.yml when enabled and the
  #     base/tool set is non-empty ──────────────────────────────────────────
  if _devbot_is_true "gpu_enabled"; then
    compose_opts+=("-f" "docker-compose.gpu.yml")
  fi

  cd "${DEV_BOT_ROOT}"
  _log "docker compose ${compose_opts[*]} up -d --no-recreate"
  docker compose "${compose_opts[@]}" up -d --no-recreate
  _ok "Docker services started"

  _reconcile_ollama_gpu
}

# ── Reconcile Ollama GPU state against gpu_enabled config ──────────────────────
# `docker compose up -d --no-recreate` never applies GPU changes to an existing
# container. When gpu_enabled flips (or the container predates GPU support),
# force-recreate ollama so its runtime state matches the config.
# gpu_enabled is the source of truth (set by ollama install.sh GPU detection);
# the host may or may not actually have a usable GPU, so tolerate failure.
_reconcile_ollama_gpu() {
  local cid
  cid=$(docker ps --filter "name=^dev-bot-ollama$" --format '{{.ID}}' 2>/dev/null | head -1)
  [[ -z "${cid}" ]] && return 0

  local has_gpu
  has_gpu=$(docker inspect "${cid}" --format '{{if .HostConfig.DeviceRequests}}true{{else}}false{{end}}' 2>/dev/null)
  [[ -z "${has_gpu}" ]] && has_gpu=false

  local gpu_enabled=false
  _devbot_is_true "gpu_enabled" && gpu_enabled=true

  if [[ "${gpu_enabled}" == "true" && "${has_gpu}" == "false" ]]; then
    _warn "gpu_enabled=true but ollama is CPU-only — recreating with GPU passthrough"
    if docker compose -f "${DEV_BOT_ROOT}/src/tools/ollama/docker-compose.yml" \
      -f "${DEV_BOT_ROOT}/docker-compose.gpu.yml" \
      up -d --force-recreate ollama; then
      _ok "ollama now running with GPU"
    else
      _warn "Could not enable GPU for ollama (host may lack a usable GPU) — leaving CPU-only"
    fi
  elif [[ "${gpu_enabled}" == "false" && "${has_gpu}" == "true" ]]; then
    _warn "gpu_enabled=false but ollama has GPU — recreating without GPU"
    if docker compose -f "${DEV_BOT_ROOT}/src/tools/ollama/docker-compose.yml" \
      up -d --force-recreate ollama; then
      _ok "ollama now running CPU-only"
    else
      _warn "Could not remove GPU from ollama"
    fi
  fi
}

# ── main ───────────────────────────────────────────────────────────────────────
main() {
  local total_start=${SECONDS}

  _header_1 "DevBot Up"

  _docker_up
  _rebuild_external_module_config
  _run_up_scripts

  echo -e "  ${TEXT_DIM}⏱  Total: $(_fmt_duration $(( SECONDS - total_start )))${TEXT_CLEAR}"
  echo
}

main "$@"
