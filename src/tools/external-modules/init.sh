#!/usr/bin/env bash
# Wire external modules into .opencode/ directories of projects.
# Idempotent — skips if already correctly linked.
#
# Usage:
#   init.sh                    # init in current directory
#   init.sh /path/to/project   # init in specified project
#
# GATE: This module must work on Ubuntu, Fedora, and macOS.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../../_shared/functions.sh
source "${MODULE_DIR}/../../_shared/functions.sh"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

# -- Shared state (populated by setup functions, read by worker functions) ---
DEV_BOT_ROOT=""
CONFIG_FILE=""
MODULES_DIR=""
PROJECT_DIR=""
MODULE_ENTRIES=""  # name\x1furl\x1flocal_path\x1fpaths_json per line (pre-built lookup)

# ── Helpers ─────────────────────────────────────────────────────────────────────

_resolve_project_dir() {
  PROJECT_DIR="${1:-$(pwd)}"
  PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd 2>/dev/null || true)"

  if [[ -z "${PROJECT_DIR}" || ! -d "${PROJECT_DIR}" ]]; then
    echo "  ${TEXT_BOLD}${TEXT_YELLOW}⚠${TEXT_CLEAR}  Directory '${1:-.}' does not exist or cannot be resolved." >&2
    exit 1
  fi
}

_resolve_paths() {
  DEV_BOT_ROOT="$(cd "${MODULE_DIR}/../../.." && pwd)"
  CONFIG_FILE="${DEV_BOT_ROOT}/.devbot.global.jsonc"
  MODULES_DIR="${DEV_BOT_ROOT}/vendor"
}

_check_config_exists() {
  if [[ ! -f "${CONFIG_FILE}" ]]; then
    _skip ".devbot.global.jsonc not found — nothing to wire"
    return 1
  fi

  if ! python3 "${MODULE_DIR}/../../_shared/read_jsonc.py" "${CONFIG_FILE}" modules >/dev/null 2>&1; then
    _skip "No modules configured in .devbot.global.jsonc"
    return 1
  fi
}

# ── Module-level worker functions (called from main loop) ────────────────────

_is_disabled() {
  local mod_name="$1"
  local disabled_json="$2"
  python3 -c "
import json, sys
disabled = json.loads('${disabled_json}')
sys.exit(0 if '${mod_name}' in disabled else 1)
" 2>/dev/null
}

_get_declared_names() {
  local mod_name="$1"
  local ext_file="${DEV_BOT_ROOT}/src/agentic/${mod_name}/external-modules.json"
  if [[ ! -f "${ext_file}" ]]; then
    ext_file="${DEV_BOT_ROOT}/src/tools/${mod_name}/external-modules.json"
  fi
  [[ -f "${ext_file}" ]] || return 1
  python3 -c "
import json
with open('${ext_file}') as f:
    for name in json.load(f).keys():
        print(name)
" 2>/dev/null || true
}

_resolve_source_dir() {
  local url="$1"
  local local_path="$2"
  if [[ -n "${local_path}" ]]; then
    echo "${local_path}"
    return 0
  elif [[ -n "${url}" ]]; then
    local vendor_rel
    vendor_rel="$(_derive_vendor_path "${url}")"
    echo "${MODULES_DIR}/${vendor_rel}"
    return 0
  fi
  return 1
}

_lookup_entry() {
  local name="$1"
  local line
  line=$(echo "${MODULE_ENTRIES}" | grep -F "${name}"$'\x1f' 2>/dev/null || true)
  echo "${line}"
}

_wire_one_module() {
  local name="$1"
  local src_dir="$2"
  local paths_json="$3"

  local paths_map
  paths_map="$(python3 -c "
import json, sys
paths = json.loads('${paths_json}')
for k, v in paths.items():
    print(f'{k}={v}')
" 2>/dev/null || true)"

  [[ -n "${paths_map}" ]] || return 0

  while IFS='=' read -r type rel_path; do
    [[ -z "${type}" || -z "${rel_path}" ]] && continue
    [[ ! -d "${src_dir}/${rel_path}" ]] && continue

    local type_src="${src_dir}/${rel_path}"
    local target_dir="${PROJECT_DIR}/.opencode/${type}"
    local link_path="${target_dir}/${name}"

    mkdir -p "${target_dir}"

    if [[ -L "${link_path}" ]]; then
      local current
      current="$(readlink "${link_path}")"
      if [[ "${current}" == "${type_src}" ]]; then
        _skip "${name} → .opencode/${type}/${name} (already correct)"
      else
        rm "${link_path}"
        ln -s "${type_src}" "${link_path}"
        _log "${name} → .opencode/${type}/${name} repaired"
      fi
    elif [[ -e "${link_path}" ]]; then
      _warn "${link_path} exists but is not a symlink — skipping"
    else
      ln -s "${type_src}" "${link_path}"
      _log "${name} → .opencode/${type}/${name} linked"
    fi
  done <<< "${paths_map}"
}

_setup_one_storage() {
  local name="$1"
  local src_dir="$2"
  local paths_json="$3"
  _setup_external_module_storage "${src_dir}" "${name}" "${paths_json}" "${DEV_BOT_ROOT}"
}

_process_agentic_module() {
  local mod_name="$1"
  local disabled_json="$2"

  _is_disabled "${mod_name}" "${disabled_json}" && return 0

  local declared_names
  declared_names=$(_get_declared_names "${mod_name}") || return 0
  [[ -n "${declared_names}" ]] || return 0

  while IFS= read -r ext_name; do
    [[ -z "${ext_name}" ]] && continue

    local entry_line
    entry_line=$(_lookup_entry "${ext_name}")
    if [[ -z "${entry_line}" ]]; then
      _warn "${ext_name}: not found in .devbot.global.jsonc modules"
      continue
    fi

    local url local_path paths_json
    IFS=$'\x1f' read -r _ url local_path paths_json <<< "${entry_line}"

    local src_dir
    src_dir=$(_resolve_source_dir "${url}" "${local_path}") || {
      _warn "${ext_name}: missing url and local_path — skipping"
      continue
    }

    if [[ -z "${local_path}" && ! -d "${src_dir}" ]]; then
      _install_one_module "${ext_name}" "${url}" "${src_dir}" "${paths_json}" || {
        _warn "${ext_name}: source not found at ${src_dir} — auto-install failed"
        continue
      }
    fi

    _wire_one_module "${ext_name}" "${src_dir}" "${paths_json}"
    _setup_one_storage "${ext_name}" "${src_dir}" "${paths_json}"
  done <<< "${declared_names}"
}

# ── Main ────────────────────────────────────────────────────────────────────────

main() {
  _resolve_project_dir "$@"
  _resolve_paths
  _check_config_exists || return 0

  # Pre-read module config and disabled modules once
  MODULE_ENTRIES=$(python3 -c "
import json, sys
sys.path.insert(0, '${MODULE_DIR}/../../_shared')
from read_jsonc import load_jsonc
data = load_jsonc('${CONFIG_FILE}')
for name, entry in data.get('modules', {}).items():
    url = entry.get('url', '')
    local_path = entry.get('local_path', '')
    paths = json.dumps(entry.get('paths', {}))
    print(f'{name}\x1f{url}\x1f{local_path}\x1f{paths}')
" 2>/dev/null || true)

  local disabled_json
  disabled_json=$(_devbot_get_disabled_modules "${PROJECT_DIR}")

  # Single loop through agentic and tool modules — each iteration calls functions only
  for module_dir in "${DEV_BOT_ROOT}/src/agentic/"*/ "${DEV_BOT_ROOT}/src/tools/"*/; do
    _process_agentic_module "$(basename "${module_dir}")" "${disabled_json}"
  done

  _ok "external-modules wiring complete"
}

main "$@"
