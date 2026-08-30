#!/usr/bin/env bash
# =============================================================================
# bin/reinit.sh
# Reinitialises dev-bot across registered projects.
# For each project in .devbot.global.jsonc::projects, runs all reset.sh scripts
# (from tools and agentic modules), then runs devbot init.
#
# Usage:
#   bin/reinit.sh                        # reinit current directory
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

  # Run all provided reset scripts
  for reset_script in "${scripts[@]}"; do
    _run_reset "${reset_script}" "${project_dir}" || true
  done

  # Re-run devbot init
  _header_3 "Running devbot init..."
  local init_start=${SECONDS}
  if bash "${DEV_BOT_ROOT}/bin/init.sh" "${project_dir}"; then
    _ok "devbot init done ($(_fmt_duration $(( SECONDS - init_start ))))"
  else
    _error "devbot init failed for ${project_dir}"
  fi
}

# ── main ───────────────────────────────────────────────────────────────────────

main() {
  local total_start=${SECONDS}

  _header_1 "DevBot Reinit"

  # ── 1. Parse arguments ───────────────────────────────────────────────────
  local all_projects=false
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
        echo "Usage: devbot reinit [--all|-a] [--full|-f]"
        echo ""
        echo "Reinitialise dev-bot for current or all registered projects."
        echo ""
        echo "Options:"
        echo "  --all, -a    Reinit all registered projects"
        echo "  --full, -f   Full reset: remove QMD collection + codebase index data"
        echo "  --help, -h   Show this help"
        exit 0
        ;;
      *)
        _warn "Unknown option: ${arg}"
        ;;
    esac
  done

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
    while IFS= read -r project_dir; do
      i=$((i + 1))
      _header_2 "Project ${i}/${project_count}: ${project_dir}"
      _reinit_project "${project_dir}" "${reset_scripts[@]}"
      echo
    done < <(echo "${projects_json}" | python3 -c "
import json, sys
for p in json.loads(sys.stdin.read()):
    print(p)
" 2>/dev/null)
  else
    # Single project: reinit current working directory
    _reinit_project "$(pwd)" "${reset_scripts[@]}"
  fi

  # ── 5. Summary ──────────────────────────────────────────────────────────
  _header_2 "✔  DevBot reinit complete"
  echo -e "  ${TEXT_DIM}⏱  Total: $(_fmt_duration $(( SECONDS - total_start )))${TEXT_CLEAR}"
  echo
}

main "$@"
