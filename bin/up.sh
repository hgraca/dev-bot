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

# The codebase-memory gateway runs as the HOST uid/gid, not root: its
# cache-ancestry check refuses to start when the process does not own the
# mounted index store. Compose interpolates these into `user:`.
export DEV_UID="$(id -u)"
export DEV_GID="$(id -g)"

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

# ── Stale container-name reclaim ───────────────────────────────────────────────
# Every dev-bot container declares a fixed `container_name` in the `dev-bot-*`
# namespace. A container created under a DIFFERENT compose project — the retired
# `dev-bot` project (renamed to `devbot` in 6cced698), or a manual `docker run`
# — is not a member of `devbot`, so `down --remove-orphans` never removes it,
# and its fixed name makes `docker compose up` fail with "Conflict. The
# container name ... is already in use", aborting the whole start. Remove such
# containers so compose can recreate them under our project. Container-local
# state is disposable: ollama models live in the bind-mounted storage/ollama.
_reclaim_stale_containers() {
  local id name project
  while IFS='|' read -r id name project; do
    [[ -n "${id}" ]] || continue
    [[ "${name}" == dev-bot-* ]] || continue
    [[ "${project}" == "devbot" ]] && continue
    _warn "removing stale container '${name}' (compose project '${project:-<none>}') — its fixed name blocks recreation"
    docker rm -f "${id}" >/dev/null 2>&1 || true
  done < <(docker ps -a --filter "name=dev-bot-" \
    --format '{{.ID}}|{{.Names}}|{{.Label "com.docker.compose.project"}}' 2>/dev/null || true)
}

# ── Docker services ────────────────────────────────────────────────────────────

_docker_up() {
  # dev-bot must be installed (global config) — report before doing anything,
  # regardless of whether any compose files are discovered.
  if [[ ! -f "${DEV_BOT_ROOT}/.devbot.global.jsonc" ]]; then
    _fatal "No .devbot.global.jsonc found at ${DEV_BOT_ROOT}/.devbot.global.jsonc — run 'make install' first."
    exit 1
  fi

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
  # GPU passthrough is a live capability probe, not just the persisted intent
  # (Docker Desktop never has it). A module that needs GPU ships a
  # docker-compose.gpu.yml beside its compose; it is included only when
  # passthrough is available AND that module's compose is selected — so the
  # overlay can never be applied without the service it overrides.
  local gpu_ok=0
  if _devbot_is_true "gpu_enabled" && _has_docker_gpu; then
    gpu_ok=1
  fi

  local compose_opts=()
  # Root-compose support is generic, not vestigial: a consumer that ships a root
  # docker-compose.yml gets it FIRST, because compose reads the project `name:`
  # from the first -f file, plus its GPU overlay when passthrough is available.
  # dev-bot itself ships no root compose (its services live per module), so this
  # block is normally skipped and the module overlays appended in the loop below
  # are what actually apply. Covered by the root-compose tests in
  # bin/tests/up_compose_opts_tests.bats.
  if [[ -f "${DEV_BOT_ROOT}/docker-compose.yml" ]]; then
    compose_opts=("-f" "docker-compose.yml")
    if [[ ${gpu_ok} -eq 1 && -f "${DEV_BOT_ROOT}/docker-compose.gpu.yml" ]]; then
      compose_opts+=("-f" "docker-compose.gpu.yml")
    fi
  fi

  local selected_composes=()
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
    selected_composes+=("${rel}")

    # The module's GPU overlay, if it ships one, follows its compose. An
    # overlay may declare `devbot:gpu-overlay-skip-if-included <compose>` to say
    # "I exist only to stand in for that compose — skip me when it is already
    # in the set". Without it a consumer fragment and its provider would both
    # apply the same device reservation (codebase-index's overlay include:s
    # ollama's).
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

  # Inside a container there is no docker daemon — the host runs the docker
  # services (reachable from here via --network host). Skip instead of
  # failing `docker compose up`.
  if ! docker info >/dev/null 2>&1; then
    _skip "no docker daemon (inside a container?) — docker services not started here; run them on the host"
    return 0
  fi

  _header_3 "Starting docker services..."

  cd "${DEV_BOT_ROOT}"
  _reclaim_stale_containers
  _log "docker compose ${compose_opts[*]} up -d --no-recreate"
  if ! docker compose "${compose_opts[@]}" up -d --no-recreate; then
    _error "docker compose up failed — docker services not started"
    return 1
  fi
  _ok "Docker services started"

  _rebuild_changed_module_images ${selected_composes[@]+"${selected_composes[@]}"}
  _reconcile_ollama_gpu
}

# ── Rebuild module images whose build input changed ───────────────────────────
# A compose service with a `build:` section is built only when its image is
# MISSING, and the `--no-recreate` above would not apply a new image to a running
# container anyway — so editing a module's Dockerfile had no effect until someone
# removed the image by hand.
#
# This rebuilds each module that builds its own image and recreates its container
# ONLY when the resulting image id actually changed, so a warm `devbot up` pays
# the (sub-second) cache-warm build but never restarts a container needlessly.
# Scope is deliberately narrow: the global `--no-recreate` behaviour is unchanged
# for everything else.
_rebuild_changed_module_images() {
  local rel dir compose image before after

  for rel in "$@"; do
    compose="${DEV_BOT_ROOT}/${rel}"
    dir="$(dirname "${rel}")"

    # Only a module that BUILDS an image can go stale this way; one that merely
    # references a published image (signoz) has nothing to rebuild.
    grep -qE '^[[:space:]]*build:' "${compose}" 2>/dev/null || continue

    # The module's own image, declared beside the build context. Every dev-bot
    # compose has a single service, so the first `image:` is the one.
    image="$(sed -n 's/^[[:space:]]*image:[[:space:]]*//p' "${compose}" | head -1)"
    [[ -n "${image}" ]] || continue

    before="$(docker image inspect "${image}" --format '{{.Id}}' 2>/dev/null || true)"
    [[ -n "${before}" ]] || continue   # no image yet — the `up` above builds it

    if ! docker compose -f "${compose}" build >/dev/null 2>&1; then
      _warn "${dir}: image build failed — keeping the current image"
      continue
    fi

    after="$(docker image inspect "${image}" --format '{{.Id}}' 2>/dev/null || true)"

    # Same id → the running container is already correct.
    [[ "${before}" == "${after}" ]] && continue

    _log "${dir}: image changed — recreating the container"
    if docker compose -f "${compose}" up -d --force-recreate >/dev/null 2>&1; then
      _ok "${dir}: container recreated on the rebuilt image"
    else
      _warn "${dir}: could not recreate the container on the new image"
    fi
  done
}

# ── Reconcile Ollama GPU state against the desired passthrough ────────────────
# `docker compose up -d --no-recreate` never applies GPU changes to an existing
# container. When the desired passthrough flips (or the container predates GPU
# support), force-recreate ollama so its runtime state matches.
# The desired state is gpu_enabled AND a live _has_docker_gpu — the persisted
# flag alone is not a capability (Docker Desktop always lacks passthrough).
# The host may or may not actually have a usable GPU, so tolerate failure.
_reconcile_ollama_gpu() {
  local cid
  cid=$(docker ps --filter "name=^dev-bot-ollama$" --format '{{.ID}}' 2>/dev/null | head -1)
  [[ -z "${cid}" ]] && return 0

  local has_gpu
  has_gpu=$(docker inspect "${cid}" --format '{{if .HostConfig.DeviceRequests}}true{{else}}false{{end}}' 2>/dev/null)
  [[ -z "${has_gpu}" ]] && has_gpu=false

  local gpu_enabled=false
  if _devbot_is_true "gpu_enabled" && _has_docker_gpu; then
    gpu_enabled=true
  fi

  if [[ "${gpu_enabled}" == "true" && "${has_gpu}" == "false" ]]; then
    _warn "gpu_enabled=true but ollama is CPU-only — recreating with GPU passthrough"
    if docker compose -f "${DEV_BOT_ROOT}/src/tools/ollama/docker-compose.yml" \
      -f "${DEV_BOT_ROOT}/src/tools/ollama/docker-compose.gpu.yml" \
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

# ── Load the repo .env into the environment ──────────────────────────────────
# Compose interpolation (`${VAR}` in a compose file) reads the environment and
# the .env in the compose PROJECT directory. With a module-first `-f` list —
# the normal case here, since there is no root compose — the project directory
# is that module's dir, so the repo-root .env is NOT consulted and a var like
# ${SIGNOZ_AUTH_TOKEN} silently interpolates to empty. Loading it here makes
# interpolation resolve for every module, and the exported vars also reach the
# module up.sh scripts (which run in this same process).
_load_env_file() {
  local env_file="${DEV_BOT_ROOT}/.env"
  [[ -f "${env_file}" ]] || return 0
  set -a
  # shellcheck disable=SC1090
  . "${env_file}"
  set +a
}

# ── main ───────────────────────────────────────────────────────────────────────
main() {
  local total_start=${SECONDS}

  _header_1 "DevBot Up"

  _load_env_file
  _docker_up
  _rebuild_external_module_config
  _run_up_scripts

  echo -e "  ${TEXT_DIM}⏱  Total: $(_fmt_duration $(( SECONDS - total_start )))${TEXT_CLEAR}"
  echo
}

main "$@"
