#!/usr/bin/env bash
# =============================================================================
# bin/reinit.sh
# Reinitialises dev-bot across registered projects.
# For each project in .devbot.global.jsonc::projects, runs all reset.sh scripts
# (from tools and agentic modules), then runs devbot init.
#
# Usage:
#   bin/reinit.sh                        # reinit current directory
#   bin/reinit.sh <project-dir>          # reinit the given project
#   bin/reinit.sh --all|-a               # reinit all registered projects
#   bin/reinit.sh --full|-f              # full reset current project
#   bin/reinit.sh --all|-a --full|-f     # full reset all registered projects
# =============================================================================

set -euo pipefail

# ── Resolve paths ──────────────────────────────────────────────────────────────
DEV_BOT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEV_BOT_ROOT

# ── Source shared library ──────────────────────────────────────────────────────
# shellcheck source=../src/_shared/functions.sh
source "${DEV_BOT_ROOT}/src/_shared/functions.sh"

# ── Helpers ────────────────────────────────────────────────────────────────────

# Read the projects array from global config
_get_projects() {
  local config="${DEV_BOT_ROOT}/.devbot.global.jsonc"
  if [[ ! -f "${config}" ]]; then
    echo "[]"
    return
  fi

  python3 -c "
import json, sys
sys.path.insert(0, '${DEV_BOT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
try:
    data = load_jsonc('${config}')
    projects = data.get('projects', [])
    print(json.dumps(projects))
except Exception as e:
    print('[]', file=sys.stderr)
" 2>/dev/null || echo "[]"
}

# Run a reset script for a given project
# If FULL_RESET is set, passes --full to the reset script
_run_reset() {
  local reset_script="$1"
  local project_dir="$2"

  if [[ ! -f "${reset_script}" || ! -x "${reset_script}" ]]; then
    return 1
  fi

  local name
  name="$(basename "$(dirname "${reset_script}")")"
  _header_3 "Running ${name} reset..."
  local start=${SECONDS}

  local -a args=("${reset_script}" "${project_dir}")
  if [[ "${FULL_RESET:-false}" == "true" ]]; then
    args+=("--full")
  fi

  if bash "${args[@]}"; then
    _ok "${name} reset done ($(_fmt_duration $(( SECONDS - start ))))"
  else
    _warn "${name} reset had issues (exit: $?)"
  fi
}

# Resolve the module-memory folders of a project, refusing anything that escapes
# it. Both `devbot_dir` and the vault path come from project-controlled input
# and the caller deletes them, so containment is checked before anything is
# touched — a symlinked `memory/active` would otherwise aim the delete elsewhere.
# Sets _MODULE_MEMORY_ACTIVE and _MODULE_MEMORY_MODULES.
_module_memory_paths() {
  local project_dir="$1"

  _MODULE_MEMORY_ACTIVE=""
  _MODULE_MEMORY_MODULES=""

  # Both paths come from `_devbot_module_memory_path`, which rejects an escaping
  # `devbot_dir` and a symlink anywhere along the vault path.
  if ! _MODULE_MEMORY_ACTIVE="$(_devbot_module_memory_path "${project_dir}" active)"; then
    _warn "reinit — refusing module memory cleanup for ${project_dir}"
    return 1
  fi

  if ! _MODULE_MEMORY_MODULES="$(_devbot_module_memory_path "${project_dir}" modules)"; then
    _warn "reinit — refusing module memory cleanup for ${project_dir}"
    return 1
  fi
}

# Reinit a single project: reset + init
_reinit_project() {
  local project_dir="$1"
  shift
  # Remaining args are reset scripts, split by marker
  local -a scripts=("$@")

  if [[ ! -d "${project_dir}" ]]; then
    _warn "Directory does not exist — skipping: ${project_dir}"
    return
  fi

  # Module memory is regenerated from scratch: every enabled module rewrites its
  # own file during init, so a module that is now disabled leaves nothing behind.
  # Validated first, before the reset scripts touch anything: a refused project
  # must not get as far as having its tree mutated, and the module writers would
  # otherwise recreate the very directory this check just refused to delete.
  local active_dir modules_dir
  if ! _module_memory_paths "${project_dir}"; then
    return 1
  fi
  active_dir="${_MODULE_MEMORY_ACTIVE}"
  modules_dir="${_MODULE_MEMORY_MODULES}"

  # Mark the wiring dirty BEFORE the reset scripts delete anything: a reinit
  # killed mid-way leaves the baseline missing, so the next `devbot` start
  # re-detects the change and repairs the tree. init.sh restores it on success.
  _devbot_clear_config_sha "${project_dir}"

  # Run all provided reset scripts
  for reset_script in "${scripts[@]}"; do
    _run_reset "${reset_script}" "${project_dir}" || true
  done

  if [[ -d "${modules_dir}" ]]; then
    rm -rf -- "${modules_dir}"
    _ok "Cleared ${modules_dir#"${project_dir}/"}"
  fi

  # Pre-modules locations. They are cleaned here, not only in the module's own
  # init.sh, because a disabled module's init never runs and would leave its
  # old copy behind as a second source.
  local legacy
  for legacy in graphify.md aws-agent-rules.md; do
    rm -f -- "${active_dir}/${legacy}"
  done

  # Re-run devbot init
  _header_3 "Running devbot init..."
  local init_start=${SECONDS}
  if bash "${DEV_BOT_ROOT}/bin/init.sh" "${project_dir}"; then
    _ok "devbot init done ($(_fmt_duration $(( SECONDS - init_start ))))"
    return 0
  fi

  # Propagate the failure: the auto-reinit caller aborts the start on a non-zero
  # reinit, so swallowing it here would launch the harness on half-built wiring
  # and re-run the same failing reinit on every later start.
  _error "devbot init failed for ${project_dir}"
  return 1
}

# ── main ───────────────────────────────────────────────────────────────────────

main() {
  local total_start=${SECONDS}
  local failed=0

  _header_1 "DevBot Reinit"

  # ── 1. Parse arguments ───────────────────────────────────────────────────
  local all_projects=false
  local target_project=""
  FULL_RESET=false

  for arg in "$@"; do
    case "${arg}" in
      --all|-a)
        all_projects=true
        ;;
      --full|-f)
        FULL_RESET=true
        ;;
      --help|-h)
        echo "Usage: devbot reinit [<project-dir>] [--all|-a] [--full|-f]"
        echo ""
        echo "Reinitialise dev-bot for a project, the current directory, or all"
        echo "registered projects."
        echo ""
        echo "Arguments:"
        echo "  <project-dir>  Project to reinit (default: current directory)"
        echo ""
        echo "Options:"
        echo "  --all, -a    Reinit all registered projects"
        echo "  --full, -f   Full reset: remove QMD collection + codebase index data"
        echo "  --help, -h   Show this help"
        exit 0
        ;;
      -*)
        _warn "Unknown option: ${arg}"
        ;;
      *)
        if [[ -n "${target_project}" ]]; then
          _error "Too many arguments: ${target_project} ${arg}"
          exit 1
        fi
        target_project="${arg}"
        ;;
    esac
  done

  # Mutually exclusive: defaulting to the broader interpretation would turn a
  # typo into a --full reset of every registered project.
  if [[ "${all_projects}" == "true" && -n "${target_project}" ]]; then
    _error "Cannot combine --all with a project path (${target_project})"
    exit 1
  fi

  if [[ "${FULL_RESET}" == "true" ]]; then
    _info "Full reset mode: QMD collections and codebase index data will be removed"
  fi

  # ── 2. Read registered projects ──────────────────────────────────────────
  local projects_json
  projects_json=$(_get_projects)

  local project_count
  project_count=$(echo "${projects_json}" | python3 -c "import json,sys; print(len(json.loads(sys.stdin.read())))" 2>/dev/null || echo "0")

  # ── 3. Discover reset scripts (unified — tools + agentic + external) ─────
  local -a reset_scripts=()
  local -a reset_base_dirs=("${DEV_BOT_ROOT}/src/tools" "${DEV_BOT_ROOT}/src/agentic" "${DEV_BOT_ROOT}/src/harnesses")
  [[ -d "${DEV_BOT_ROOT}/storage/external-agentic-modules" ]] && reset_base_dirs+=("${DEV_BOT_ROOT}/storage/external-agentic-modules")

  while IFS= read -r script; do
    [[ -n "${script}" ]] && reset_scripts+=("${script}")
  done < <(_collect_module_scripts "reset.sh" "${reset_base_dirs[@]}")

  _info "Found ${#reset_scripts[@]} reset script(s)"

  # ── 4. Determine mode: single project or all ─────────────────────────────
  if [[ "${all_projects}" == "true" ]]; then
    # --all: process every registered project
    if [[ ${project_count} -eq 0 ]]; then
      _info "No projects registered in .devbot.global.jsonc::projects"
      _info "Run 'devbot init' in a project to register it first."
      exit 0
    fi

    _info "Found ${project_count} registered project(s):"
    echo "${projects_json}" | python3 -c "
import json, sys
for p in json.loads(sys.stdin.read()):
    print(f'    {p}')
" 2>/dev/null
    echo

    local i=0
    # Each per-project init emits only a compact env-var notice; the single
    # end-of-run dialog below shows the union across all projects.
    export DEV_BOT_DEFER_ENV_DIALOG=1
    while IFS= read -r project_dir; do
      i=$((i + 1))
      _header_2 "Project ${i}/${project_count}: ${project_dir}"
      _reinit_project "${project_dir}" "${reset_scripts[@]}" || failed=1
      echo
    done < <(echo "${projects_json}" | python3 -c "
import json, sys
for p in json.loads(sys.stdin.read()):
    print(p)
" 2>/dev/null)
    unset DEV_BOT_DEFER_ENV_DIALOG

    # ── 4b. End-of-run env-var dialog (union across every processed project) ──
    # init.sh only warned per project (deferred). Present the union once:
    # collect refs from all projects, dedupe, and run the full notice + ack.
    local union_refs=""
    while IFS= read -r project_dir; do
      [[ -d "${project_dir}" ]] || continue
      local proj_refs
      proj_refs="$(_devbot_missing_mcp_env_vars "${project_dir}")"
      if [[ -n "${proj_refs}" ]]; then
        union_refs+="${proj_refs}"$'\n'
      fi
    done < <(echo "${projects_json}" | python3 -c "
import json, sys
for p in json.loads(sys.stdin.read()):
    print(p)
" 2>/dev/null)

    if [[ -n "${union_refs}" ]]; then
      # Dedupe identical ref lines across projects (same module+server+key+var).
      local deduped
      deduped="$(echo "${union_refs}" | awk '!seen[$0]++')"
      _devbot_present_missing_env_vars "${deduped}" ack
    fi
  elif [[ -n "${target_project}" ]]; then
    if [[ ! -d "${target_project}" ]]; then
      _error "Not a directory: ${target_project}"
      exit 1
    fi
    _reinit_project "$(cd "${target_project}" && pwd)" "${reset_scripts[@]}" || failed=1
  else
    # Single project: reinit current working directory
    _reinit_project "$(pwd)" "${reset_scripts[@]}" || failed=1
  fi

  # ── 5. Summary ──────────────────────────────────────────────────────────
  if [[ "${failed}" -ne 0 ]]; then
    _error "Reinit failed — fix the cause and re-run 'devbot reinit'."
    echo
    exit 1
  fi

  _header_2 "✔  DevBot reinit complete"
  echo -e "  ${TEXT_DIM}⏱  Total: $(_fmt_duration $(( SECONDS - total_start )))${TEXT_CLEAR}"
  echo
}

main "$@"
