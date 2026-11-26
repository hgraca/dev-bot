#!/usr/bin/env bash
# =============================================================================
# bin/up.sh
# Runs all up.sh scripts discovered under src/. Intended to be called after
# docker services are up (e.g., pull models, wait for dependencies).
#
# Usage:
#   bin/up.sh                    # run in current directory
#   bin/up.sh /path/to/project   # run in specified project
#   bin/up.sh --is-up [/path]    # silent probe: exit 0 iff every declared docker
#                                # service is already running (used by `devbot`)
#   bin/up.sh --if-needed [/path]  # run the sequence unless a start completed
#                                  # while waiting for the install-level up lock
#   bin/up.sh --owner <name> [/path]
#                                # ...and register <name> as an owner of the
#                                # stack once the start completes (pid: the
#                                # invoking process, or --owner-pid <pid>). A
#                                # non-session owner (herdr) keeps the containers
#                                # alive after every devbot session has exited;
#                                # see the ownership registry in functions.sh.
#
# Adding a new up step:
#   Create src/tools/<module>/up.sh, src/agentic/<module>/up.sh or
#   src/harnesses/<module>/up.sh — it will be auto-discovered and run.
# =============================================================================

set -euo pipefail

DEV_BOT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEV_BOT_ROOT

# Two consumers. Compose interpolates these into `user:` for a service that
# starts directly as the host uid (mdctx); codebase-memory passes them to its
# entrypoint instead, which chowns the store volume and then drops privileges to
# them — its store is a named volume, so `user:` would remove the chown it needs.
DEV_UID="$(id -u)"
export DEV_UID
DEV_GID="$(id -g)"
export DEV_GID

# ── Source shared library ──────────────────────────────────────────────────────
# shellcheck source=../src/_shared/functions.sh
source "${DEV_BOT_ROOT}/src/_shared/functions.sh"

# ── Failure reporting ─────────────────────────────────────────────────────────
# `set -e` aborts on the first unguarded failure — which on its own exits the
# script with no line saying what broke, and the caller then tears the
# containers down. Every abort is reported instead, naming the step in
# progress: the command that failed and its line only tell half the story.
_UP_STEP="startup"

_up_failed() {
  local rc="${1:-1}" line="${2:-?}" cmd="${3:-?}"
  _error "devbot up failed during '${_UP_STEP}' (exit ${rc}, line ${line})."
  _error "  failing command: ${cmd}"
  _error "  fix the cause above, then re-run 'devbot up'."
}

# Installs the trap. `set -E` is what makes it fire inside functions and
# subshells, not only at top level — where most of this script's work happens.
_up_install_trap() {
  set -E
  trap '_up_failed "$?" "${LINENO}" "${BASH_COMMAND}"' ERR
}

# The codebase-memory gateway mounts ONE repo root
# (${CODEBASE_MEMORY_ROOT:-$HOME}, see its compose) at the same absolute path.
# It is resolved in main() after .env is loaded — see
# _devbot_resolve_codebase_memory_root — and exported before compose
# interpolates it.

# ── `--is-up` probe (internal; the bare `devbot` start asks before running) ───
UP_IS_UP=0
UP_IF_NEEDED=0
UP_OWNER=""
UP_OWNER_PID=""
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --is-up)
      UP_IS_UP=1
      shift
      ;;
    --if-needed)
      UP_IF_NEEDED=1
      shift
      ;;
    --owner)
      [[ -n "${2:-}" ]] || { _fatal "--owner needs a name"; exit 1; }
      UP_OWNER="$2"
      shift 2
      ;;
    --owner-pid)
      [[ -n "${2:-}" ]] || { _fatal "--owner-pid needs a pid"; exit 1; }
      UP_OWNER_PID="$2"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      _fatal "unknown option: $1"
      exit 1
      ;;
  esac
done
# A caller that names itself an owner gets recorded as one after the start: the
# pid is validated here, where a typo is still the caller's error to see.
if [[ -z "${UP_OWNER}" && -n "${UP_OWNER_PID}" ]]; then
  _fatal "--owner-pid names the process of an owner — pass --owner too"
  exit 1
fi
if [[ -n "${UP_OWNER}" ]]; then
  _devbot_owner_name_ok "${UP_OWNER}" || { _fatal "invalid owner name '${UP_OWNER}'"; exit 1; }
  UP_OWNER_PID="${UP_OWNER_PID:-$PPID}"
  # A canonical positive pid only: 0 is a process group, 007 names nothing.
  [[ "${UP_OWNER_PID}" =~ ^[1-9][0-9]*$ ]] \
    || { _fatal "invalid owner pid '${UP_OWNER_PID}'"; exit 1; }
fi

PROJECT_DIR="$(cd "${1:-$(pwd)}" && pwd 2>/dev/null || true)"

if [[ -z "${PROJECT_DIR}" || ! -d "${PROJECT_DIR}" ]]; then
  _fatal "Directory '${1:-.}' does not exist or cannot be resolved."
  exit 1
fi

_run_up_scripts() {
  _header_2 "Up Scripts"
  _run_service_scripts "up.sh" "${PROJECT_DIR}"
}

# Surface a project outside the codebase-memory gateway's bind root: it is
# silently skipped by index-project.sh, so the index stays empty with no console
# signal otherwise. Only when the codebase-memory engine is active.
_check_codebase_memory_scope() {
  # Stay silent unless the disabled-set read AND its parse both succeed: a
  # missing python3 or an unparseable config must not be read as "engine active"
  # and warn spuriously.
  local disabled active
  disabled="$(_devbot_get_disabled_modules "${PROJECT_DIR}" 2>/dev/null)" || return 0
  active="$(printf '%s' "${disabled}" \
    | python3 -c "import json,sys; print(0 if 'codebase-memory' in json.load(sys.stdin) else 1)" 2>/dev/null)" || return 0
  [[ "${active}" == "1" ]] || return 0
  _devbot_warn_codebase_memory_scope "${PROJECT_DIR}" "${CODEBASE_MEMORY_ROOT}"
}

# ── External module config (rebuild from internal module declarations) ──────────

_rebuild_external_module_config() {
  _header_2 "External Module Config"

  local config_file="${DEV_BOT_ROOT}/.devbot.global.jsonc"
  if [[ ! -f "${config_file}" ]]; then
    _error "No .devbot.global.jsonc found at ${config_file} — run 'make install' first."
    return 1
  fi

  # Whether the baseline was clean BEFORE the merge. Only a clean baseline may
  # be refreshed after it: a missing or already-stale baseline means a reinit is
  # pending, and writing here would silently consume it — a standalone
  # `devbot up` / `make up` must never clear the auto-reinit trigger.
  local baseline_was_clean=0
  if [[ -f "${PROJECT_DIR}/.devbot.project.jsonc" ]] \
    && ! _devbot_config_changed "${PROJECT_DIR}"; then
    baseline_was_clean=1
  fi

  # Delegates to the shared rebuild: every module's declarations are merged
  # regardless of enablement — the config store and the vendor/ clones are
  # global, shared by every project. See _devbot_rebuild_external_module_config.
  _devbot_rebuild_external_module_config

  # The merge rewrites the global config, which the per-project wiring baseline
  # hashes — and init.sh recorded that baseline BEFORE this start's merge ran.
  # Refresh a CLEAN baseline so the next start does not read a spurious "config
  # changed" and reinit again (audit-71 C2).
  if [[ "${baseline_was_clean}" -eq 1 ]]; then
    _devbot_write_config_sha "${PROJECT_DIR}"
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

# ── Compose `-f` list (memoised) ───────────────────────────────────────────────
# Fills COMPOSE_OPTS (the -f list) and SELECTED_COMPOSES (the module-relative
# paths of the selected composes, for the image rebuild). Memoised because
# main() needs the same set to pre-create bind-mount sources before _docker_up
# runs, and the "disabled per config" messages must be printed once.
COMPOSE_OPTS=()
SELECTED_COMPOSES=()
_COMPOSE_OPTS_BUILT=0

_compose_opts() {
  if [[ "${_COMPOSE_OPTS_BUILT}" -eq 1 ]]; then
    return 0
  fi
  _COMPOSE_OPTS_BUILT=1

  # ── Discover docker-compose.yml files across every module base dir ─────
  # (tools + agentic + harnesses). Since v1.4 docker services start only when
  # an ENABLED module needs them: a module disabled in the `modules` map has
  # its compose excluded, and a consumer module that needs a provider's
  # service ships its own fragment that `include:`s the provider compose (so
  # the provider boots even when its own module is disabled). If NO enabled
  # module ships a compose file, docker has nothing to start — skip the whole
  # section silently (no header, no `docker compose` invocation).
  # Pass the project dir: the effective set is global ∘ per-project, so omitting
  # it would read the global map alone — silently excluding the compose of any
  # module that is false globally and enabled by this project (e.g. signoz).
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
  # GPU passthrough is a live capability probe, not just the persisted intent
  # (Docker Desktop never has it). A module that needs GPU ships a
  # docker-compose.gpu.yml beside its compose; it is included only when
  # passthrough is available AND that module's compose is selected — so the
  # overlay can never be applied without the service it overrides.
  local gpu_ok=0
  if _devbot_is_true "gpu_enabled" && _has_docker_gpu; then
    gpu_ok=1
  fi

  COMPOSE_OPTS=()
  # Root-compose support is generic, not vestigial: a consumer that ships a root
  # docker-compose.yml gets it FIRST, because compose reads the project `name:`
  # from the first -f file, plus its GPU overlay when passthrough is available.
  # dev-bot itself ships no root compose (its services live per module), so this
  # block is normally skipped and the module overlays appended in the loop below
  # are what actually apply. Covered by the root-compose tests in
  # bin/tests/up_compose_opts_tests.bats.
  if [[ -f "${DEV_BOT_ROOT}/docker-compose.yml" ]]; then
    COMPOSE_OPTS=("-f" "docker-compose.yml")
    if [[ ${gpu_ok} -eq 1 && -f "${DEV_BOT_ROOT}/docker-compose.gpu.yml" ]]; then
      COMPOSE_OPTS+=("-f" "docker-compose.gpu.yml")
    fi
  fi

  SELECTED_COMPOSES=()
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
    COMPOSE_OPTS+=("-f" "${rel}")
    SELECTED_COMPOSES+=("${rel}")

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
      if [[ -n "${skip_if}" ]] && printf '%s\n' "${COMPOSE_OPTS[@]}" | grep -Fxq "${skip_if}"; then
        _skip "${mod_name}: GPU overlay skipped — ${skip_if} already applies it"
      else
        COMPOSE_OPTS+=("-f" "${gpu_rel}")
      fi
    fi
  done
}

# ── Announce the images `up` is about to download ─────────────────────────────
# `docker compose up` pulls a missing image without asking. The layers arrive
# under compose's own output, and a first run can spend minutes and several GB
# there — so name what is being downloaded first, or the wait reads as a hang.
# A service that builds its own image is skipped: compose builds it locally.
_announce_missing_images() {
  # Best effort: when the model cannot be resolved (compose missing, config
  # broken) the `up` below reports the real error — staying silent here avoids
  # inventing a second, less accurate one.
  local model
  model="$(docker compose "${COMPOSE_OPTS[@]}" config --format json 2>/dev/null)" || return 0
  [[ -n "${model}" ]] || return 0

  local images
  images="$(printf '%s' "${model}" | python3 -c '
import json, sys

data = json.load(sys.stdin)
seen = set()
for service in (data.get("services") or {}).values():
    if service.get("build"):
        continue
    image = service.get("image")
    if image and image not in seen:
        seen.add(image)
        print(image)
' 2>/dev/null)" || return 0
  [[ -n "${images}" ]] || return 0

  local -a missing=()
  local image
  while IFS= read -r image; do
    [[ -n "${image}" ]] || continue
    docker image inspect "${image}" >/dev/null 2>&1 || missing+=("${image}")
  done <<< "${images}"
  [[ ${#missing[@]} -gt 0 ]] || return 0

  _warn "${#missing[@]} image(s) not present locally — downloading now (this can take several GB):"
  for image in "${missing[@]}"; do
    echo -e "      ${TEXT_DIM}• ${image}${TEXT_CLEAR}"
  done
}

# ── Docker services ────────────────────────────────────────────────────────────

_docker_up() {
  # dev-bot must be installed (global config) — report before doing anything,
  # regardless of whether any compose files are discovered.
  if [[ ! -f "${DEV_BOT_ROOT}/.devbot.global.jsonc" ]]; then
    _fatal "No .devbot.global.jsonc found at ${DEV_BOT_ROOT}/.devbot.global.jsonc — run 'make install' first."
    exit 1
  fi

  _compose_opts

  if [[ ${#COMPOSE_OPTS[@]} -eq 0 ]]; then
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
  _announce_missing_images
  _log "docker compose ${COMPOSE_OPTS[*]} up -d --no-recreate"
  if ! docker compose "${COMPOSE_OPTS[@]}" up -d --no-recreate; then
    _error "docker compose up failed — docker services not started"
    return 1
  fi
  _ok "Docker services started"

  _rebuild_changed_module_images ${SELECTED_COMPOSES[@]+"${SELECTED_COMPOSES[@]}"}
  _reconcile_ollama_gpu
}

# ── Up stamp ──────────────────────────────────────────────────────────────────
# A completed start records the project it served and the wiring it ran on. The
# compose scan cannot see what a module's own up.sh starts (the datasources
# gateway is rendered per project), so liveness alone would skip a project's
# first start whenever another project held the shared services up.
_up_stamp_path() {
  local key
  key="$(printf '%s' "$1" | cksum | cut -d' ' -f1)"
  printf '%s/run/up/%s.stamp' "${DEV_BOT_ROOT}/storage" "${key}"
}

# Every container the install owns, module-owned ones included — a module up.sh
# may start what the compose scan cannot see (the datasources gateway), and a
# stamp that ignored it would skip its recreation after it stops.
_devbot_owned_containers() {
  docker ps --filter "label=com.docker.compose.project=devbot" \
    --format '{{.Names}}' 2>/dev/null | sort
}

_write_up_stamp() {
  local path sha root pw_root containers
  path="$(_up_stamp_path "${PROJECT_DIR}")"
  sha="$(_devbot_wiring_sha "${PROJECT_DIR}")"
  root="$(_devbot_codebase_memory_root)"
  pw_root="$(_devbot_stamp_playwright_root 2>/dev/null || true)"
  containers="$(_devbot_owned_containers)"
  # An empty container list describes nothing: no stamp is better than one that
  # would vouch for a start whose containers the probe cannot see. A gateway root
  # that will not resolve is the same case — the mount it describes is unknown.
  [[ -n "${sha}" && -n "${containers}" && -n "${pw_root}" ]] || return 0
  mkdir -p "$(dirname "${path}")" 2>/dev/null || return 0
  {
    printf '%s\n%s\n%s\n%s\n' "${PROJECT_DIR}" "${sha}" "${root}" "${pw_root}"
    printf '%s\n' "${containers}"
  } > "${path}" 2>/dev/null || true
}

# The gateway's bind mount is fixed at container creation and only a module
# up.sh recreates it, so a changed desired root must not be skipped over. A
# module script that failed was tolerated by the start, not completed by it.
_start_complete() { [[ "${MODULE_SCRIPT_FAILED:-0}" -eq 0 ]]; }

# A completed start is recorded; anything else leaves no record at all. The
# stamp is cleared when the run starts and again on a tolerated failure, so the
# previous success can never vouch for work this run did not finish.
_clear_up_stamp() { rm -f "$(_up_stamp_path "${PROJECT_DIR}")"; }

_record_start() {
  if _start_complete; then
    _write_up_stamp
  else
    _clear_up_stamp
    _warn "module scripts failed — no up stamp; the next start retries the up sequence"
  fi
}

_up_stamp_matches() {
  local path line i name live
  local -a lines=()
  path="$(_up_stamp_path "${PROJECT_DIR}")"
  [[ -f "${path}" ]] || return 1
  while IFS= read -r line; do lines+=("${line}"); done < "${path}"
  [[ ${#lines[@]} -ge 4 ]] || return 1
  [[ "${lines[0]}" == "${PROJECT_DIR}" ]] || return 1
  [[ -n "${lines[1]}" && "${lines[1]}" == "$(_devbot_wiring_sha "${PROJECT_DIR}")" ]] || return 1
  [[ "${lines[2]}" == "$(_devbot_codebase_memory_root)" ]] || return 1
  # A changed playwright root means the running container's bind mount is stale.
  [[ "${lines[3]}" == "$(_devbot_stamp_playwright_root 2>/dev/null)" ]] || return 1

  live="$(_devbot_owned_containers)" || return 1
  for ((i = 4; i < ${#lines[@]}; i++)); do
    name="${lines[$i]}"
    [[ -n "${name}" ]] || continue
    grep -Fxq "${name}" <<< "${live}" || return 1
  done
}

# ── Already-up probe ──────────────────────────────────────────────────────────
# `bin/up.sh --is-up`: exit 0 only when this project's start already completed
# here and every docker service it declares is still running. Silent, read-only.
_up_is_up() {
  [[ -f "${DEV_BOT_ROOT}/.devbot.global.jsonc" ]] || return 1
  docker info >/dev/null 2>&1 || return 1
  # The stamp records the gateways' desired mount roots, so the probe must see
  # the same .env main() loads before resolving them.
  _load_env_file >/dev/null 2>&1 || true
  # The compose set includes a mandatory PLAYWRIGHT_ROOT; without it compose
  # aborts before answering, and the probe would report every start as needed.
  _devbot_probe_playwright_root >/dev/null 2>&1 || return 1
  _up_stamp_matches || return 1

  # Same selection `_docker_up` uses; its disabled-module notes are chatter the
  # caller must not see.
  _compose_opts >/dev/null 2>&1 || return 1
  [[ ${#COMPOSE_OPTS[@]} -gt 0 ]] || return 1

  local declared running service
  # Relative -f paths and compose's .env lookup are anchored at DEV_BOT_ROOT.
  declared="$(cd "${DEV_BOT_ROOT}" && docker compose "${COMPOSE_OPTS[@]}" config --services 2>/dev/null)" || return 1
  [[ -n "${declared}" ]] || return 1
  running="$(cd "${DEV_BOT_ROOT}" && docker compose "${COMPOSE_OPTS[@]}" ps --status running --services 2>/dev/null)" || return 1

  while IFS= read -r service; do
    [[ -n "${service}" ]] || continue
    grep -Fxq "${service}" <<< "${running}" || return 1
  done <<< "${declared}"
}

# ── Up lock ───────────────────────────────────────────────────────────────────
# One sequence per install: the containers
# and the gateway are shared by every project.
# `--if-needed` waits, re-probes, then skips or runs;
# a failed wait warns and re-probes too.
_up_run_locked() {
  local cap="${DEVBOT_UP_LOCK_WAIT:-600}"
  if ! _devbot_lock_wait "$(_devbot_up_lock_path)" "${cap}"; then
    _warn "up lock not held — continuing unlocked; concurrent starts may overlap (cap ${cap}s, DEVBOT_UP_LOCK_WAIT)"
  fi

  # Probed after the wait either way: locked, the stamp cannot change under us;
  # unlocked, a start that finished at the boundary still must not run twice.
  if [[ "${UP_IF_NEEDED}" -eq 1 ]] && _up_is_up; then
    _skip "devbot services already running — skipping 'devbot up'"
    # A skipped start still leaves the stack up, which is exactly what the
    # owner asked for — so the claim is recorded either way.
    _up_register_owner
    return 0
  fi

  _up_install_trap
  main "$@"
  # Reached only on success: a failure aborts through the ERR trap, and a
  # failed start must never leave a claim vouching for containers it did not
  # bring up.
  _up_register_owner
}

# ── Owner registration ─────────────────────────────────────────────────────────
# A caller that is not a devbot session can own the stack (herdr runs this and
# opens its own panes), and the last-session teardown must then leave it alone.
# Called while the up lock is held, before it is released — the claim takes the
# registry lock, so it stays inside the up → registry order.
_up_register_owner() {
  [[ -n "${UP_OWNER}" ]] || return 0
  if _devbot_owner_claim "${UP_OWNER}" "${UP_OWNER_PID}"; then
    _ok "container owner registered: ${UP_OWNER} (pid ${UP_OWNER_PID})"
  else
    # The claim is the only thing protecting this stack from the next session
    # exit's teardown, so a silent miss would be worse than the warning.
    _warn "container owner '${UP_OWNER}' NOT registered — the next last-session exit removes these containers"
  fi
}

# ── Writable bind-mount sources ────────────────────────────────────────────────
# Docker creates a missing bind-mount SOURCE on the host as root:root. A module
# service that runs as the host uid (e.g. mdctx-mcp) then finds its own writable
# state dir owned by root and refuses to start:
#   exact executable identity could not be verified (cache-private)
#   - <dir>: owner uid 0, expected euid <uid>
# (codebase-memory used to be the other case; its store is a named volume now, so
# it is out of this path.)
# It only ever bites where nothing created the dir first: on a warm machine the
# dir already exists, so nobody looks. Create the WRITABLE sources ourselves, as
# the host user, before compose can get there.
# Deliberately one-sided: a missing READ-ONLY source is a misconfiguration (the
# module would mount an empty dir), so it must fail loudly and is never
# fabricated here. The same holds for a writable source that declares
# create_host_path: false — the module is saying its absence is an error, so the
# model is consulted rather than assumed.
_ensure_writable_bind_sources() {
  if [[ ! -f "${DEV_BOT_ROOT}/.devbot.global.jsonc" ]]; then
    return 0
  fi

  _compose_opts
  if [[ ${#COMPOSE_OPTS[@]} -eq 0 ]]; then
    return 0
  fi

  # Inside a container there is no docker daemon — the host starts the services.
  if ! docker info >/dev/null 2>&1; then
    return 0
  fi

  # Relative -f paths (and compose's .env lookup) are anchored at DEV_BOT_ROOT.
  cd "${DEV_BOT_ROOT}"

  local model
  model="$(docker compose "${COMPOSE_OPTS[@]}" config --format json 2>/dev/null)" || {
    _warn "could not resolve the compose model — writable mount sources not pre-created"
    return 0
  }

  local source
  while IFS= read -r source; do
    if [[ -z "${source}" ]]; then
      continue
    fi
    if [[ -d "${source}" ]]; then
      continue
    fi
    if (umask 077 && mkdir -p "${source}") 2>/dev/null; then
      _ok "created writable mount source ${source}"
    else
      _warn "could not create mount source ${source}"
    fi
  done < <(printf '%s' "${model}" | python3 -c '
import json, sys

try:
    model = json.load(sys.stdin)
except ValueError:
    sys.exit(0)

seen = set()
for service in model.get("services", {}).values():
    for volume in service.get("volumes") or []:
        if volume.get("type") != "bind" or volume.get("read_only"):
            continue
        # Honour the mount contract: create_host_path: false means a missing
        # source is a misconfiguration that must fail loudly, so it is never
        # fabricated here either.
        if (volume.get("bind") or {}).get("create_host_path", True) is False:
            continue
        source = volume.get("source")
        if source and source not in seen:
            seen.add(source)
            print(source)
' 2>/dev/null)

  return 0
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
#
# The loader is shared so every consumer agrees on precedence: a blank
# placeholder in the template never erases a value exported in the shell.
_load_env_file() {
  _devbot_load_env_file "${DEV_BOT_ROOT}/.env"
}

# ── Resolve and persist the codebase-memory gateway root ─────────────────────
# An explicit CODEBASE_MEMORY_ROOT (process env or repo .env) is the operator's
# declared root; persist it so a later ENV-LESS invocation — the harness-launch
# `devbot`, which carries no such variable — resolves the same mount instead of
# recreating the gateway on the derived default and dropping the project
# (audit-80 FAIL-3). A derived root is NOT persisted, so a newly registered
# project outside $HOME still widens it automatically. Runs after .env is
# loaded and before compose interpolates the value.
_devbot_resolve_codebase_memory_root() {
  local explicit="${CODEBASE_MEMORY_ROOT:-}" resolved baseline_clean=0
  resolved="$(_devbot_codebase_memory_root)"
  export CODEBASE_MEMORY_ROOT="${resolved}"
  if [[ -n "${explicit}" ]]; then
    # Persisting rewrites the global config, which the wiring baseline hashes;
    # refresh the baseline afterwards so the next start does not read the change
    # as a pending reinit. Only when none was pending (never consume one).
    _devbot_config_changed "${PROJECT_DIR}" || baseline_clean=1
    _devbot_persist_codebase_memory_root "${explicit}"
    if [[ "${baseline_clean}" == "1" ]]; then
      _devbot_write_config_sha "${PROJECT_DIR}"
    fi
  fi
}

# ── Resolve the Playwright gateway's mount root ──────────────────────────────
# The compose file interpolates PLAYWRIGHT_ROOT as mandatory, and three entry
# points hand it to docker: `main()` here, `--is-up`, and `bin/down.sh`. Each
# resolves it through the shared helper, so none of them can forget.
# A project that disables the module selects no such file, so its knob must not
# abort the start — and the stamp must agree, or it would never match.
_devbot_playwright_enabled() {
  ! _devbot_get_disabled_modules "${PROJECT_DIR}" 2>/dev/null \
    | tr -d '[]" ' | tr ',' '\n' | grep -Fxq playwright
}

_devbot_resolve_playwright_root() {
  _devbot_playwright_enabled || return 0
  local explicit="${PLAYWRIGHT_ROOT:-}" baseline_clean=0
  _devbot_export_playwright_root || return 1
  # Persist an explicit root: the gateway is one shared container, so a value
  # that lives only in one invocation would recreate it under every other
  # project's live sessions on the next start.
  if [[ -n "${explicit}" ]]; then
    _devbot_config_changed "${PROJECT_DIR}" || baseline_clean=1
    _devbot_persist_playwright_root "${explicit}"
    if [[ "${baseline_clean}" == "1" ]]; then
      _devbot_write_config_sha "${PROJECT_DIR}"
    fi
  fi
  return 0
}

# Read-only variant for the liveness probe: resolves and exports, never writes
# configuration. A probe that persisted a value would mutate the state it exists
# to inspect (the global config, and the wiring sha that hashes it).
_devbot_probe_playwright_root() {
  _devbot_playwright_enabled || return 0
  _devbot_export_playwright_root
}

# The root the up stamp records. "-" for a disabled module: nothing interpolates
# the file, so the knob is not part of the recorded state — but the line must
# still exist, keeping the container names at index 4.
_devbot_stamp_playwright_root() {
  _devbot_playwright_enabled || {
    printf '%s\n' '-'
    return 0
  }
  _devbot_playwright_root
}

# ── main ───────────────────────────────────────────────────────────────────────
main() {
  local total_start=${SECONDS}

  _header_1 "DevBot Up"

  # Invalidate the previous record first: an abort at ANY later step (compose,
  # a module script, the ERR trap) must not leave the old stamp vouching for a
  # start this run did not complete.
  _clear_up_stamp

  _UP_STEP="environment"
  _load_env_file
  _UP_STEP="codebase-memory root"
  _devbot_resolve_codebase_memory_root
  _UP_STEP="playwright root"
  _devbot_resolve_playwright_root
  _UP_STEP="codebase-memory scope"
  _check_codebase_memory_scope
  _UP_STEP="bind-mount sources"
  _ensure_writable_bind_sources
  _UP_STEP="docker services"
  _docker_up
  _UP_STEP="external module config"
  _rebuild_external_module_config
  _UP_STEP="module up scripts"
  _run_up_scripts

  _record_start

  echo -e "  ${TEXT_DIM}⏱  Total: $(_fmt_duration $(( SECONDS - total_start )))${TEXT_CLEAR}"
  echo
}

# Only when executed: this file is SOURCED by its tests, and an ERR trap (or
# `set -E`) installed there would leak into the calling shell. `-E` is what
# makes the trap fire inside functions and subshells, not just at top level.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ "${UP_IS_UP}" -eq 1 ]]; then
    _up_is_up && exit 0
    exit 1
  fi
  _up_run_locked "$@"
  exit $?
fi

main "$@"
