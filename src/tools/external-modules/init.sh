#!/usr/bin/env bash
# Wire external modules into the project devbot dir (.agents/) — harness-agnostic.
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
# DEV_BOT_ROOT is exported by _shared/functions.sh at source time (respecting a
# pre-set env value) and refined by _resolve_paths — do not pre-declare it empty.
CONFIG_FILE=""
MODULES_DIR=""
PROJECT_DIR=""
MODULE_ENTRIES=""  # name\x1furl\x1fpath\x1fpaths_json per line (pre-built lookup)
PROCESSED_NAMES="" # names already wired by the declared-module loop (newline-separated)

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
  # DEV_BOT_ROOT/CONFIG_FILE/MODULES_DIR may be pre-set (tests run against a sandbox).
  DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "${MODULE_DIR}/../../.." && pwd)}"
  CONFIG_FILE="${CONFIG_FILE:-${DEV_BOT_ROOT}/.devbot.global.jsonc}"
  MODULES_DIR="${MODULES_DIR:-${DEV_BOT_ROOT}/vendor}"
}

_check_config_exists() {
  if [[ ! -f "${CONFIG_FILE}" ]]; then
    _skip ".devbot.global.jsonc not found — nothing to wire"
    return 1
  fi

  if ! python3 "${MODULE_DIR}/../../_shared/read_jsonc.py" "${CONFIG_FILE}" external_modules >/dev/null 2>&1; then
    _skip "No modules configured in .devbot.global.jsonc"
    return 1
  fi
}

# ── Module-level worker functions (called from main loop) ────────────────────

_is_disabled() {
  local mod_name="$1"
  local disabled_json="$2"
  jq -e --arg m "${mod_name}" 'index($m) != null' <<< "${disabled_json}" >/dev/null 2>&1
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
  local path="$2"
  # path (local dir) takes precedence over url — lets a config entry point a
  # declared repo at a local checkout; never cloned into vendor/.
  if [[ -n "${path}" ]]; then
    echo "${path}"
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

  # External artifacts go into the DEVBOT DIR (e.g. .agents/), like the
  # internal artifacts — NOT .opencode/ — so both harnesses get them through
  # the harness delegation (.claude/* → .agents/*) and opencode's direct
  # .agents discovery. Each external module is its own namespace under the
  # type dir (.agents/skills/addyosmani, .agents/agents/addyosmani, ...).
  local devbot_dir
  devbot_dir="$(_devbot_get_project_dir "${PROJECT_DIR}")"

  while IFS='=' read -r type rel_path; do
    [[ -z "${type}" || -z "${rel_path}" ]] && continue
    [[ ! -d "${src_dir}/${rel_path}" ]] && continue

    local type_src="${src_dir}/${rel_path}"
    local target_dir="${PROJECT_DIR}/${devbot_dir}/${type}"
    local link_path="${target_dir}/${name}"

    # The name may be namespaced (org/repo, local/folder) — create the parent
    # dirs so the link lands at .agents/<type>/<org>/<repo>.
    mkdir -p "$(dirname "${link_path}")"

    if [[ -L "${link_path}" ]]; then
      local current
      current="$(readlink "${link_path}")"
      if [[ "${current}" == "${type_src}" ]]; then
        _skip "${name} → ${devbot_dir}/${type}/${name} (already correct)"
      else
        rm "${link_path}"
        ln -s "${type_src}" "${link_path}"
        _log "${name} → ${devbot_dir}/${type}/${name} repaired"
      fi
    elif [[ -e "${link_path}" ]]; then
      _warn "${link_path} exists but is not a symlink — skipping"
    else
      ln -s "${type_src}" "${link_path}"
      _log "${name} → ${devbot_dir}/${type}/${name} linked"
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

    # External modules are also enable/disable-able via the "modules" map.
    if _is_disabled "${ext_name}" "${disabled_json}"; then
      _skip "${ext_name}: disabled — skipping"
      continue
    fi

    local entry_line
    entry_line=$(_lookup_entry "${ext_name}")
    if [[ -z "${entry_line}" ]]; then
      _warn "${ext_name}: not found in .devbot.global.jsonc external_modules"
      continue
    fi

    local url path paths_json
    IFS=$'\x1f' read -r _ url path paths_json <<< "${entry_line}"

    local src_dir
    src_dir=$(_resolve_source_dir "${url}" "${path}") || {
      _warn "${ext_name}: missing url and path — skipping"
      continue
    }

    if [[ -n "${path}" && ! -d "${src_dir}" ]]; then
      _warn "${ext_name}: local path not found (${path})"
      continue
    fi

    if [[ -z "${path}" && ! -d "${src_dir}" ]]; then
      _install_one_module "${ext_name}" "${url}" "${src_dir}" "${paths_json}" || {
        _warn "${ext_name}: source not found at ${src_dir} — auto-install failed"
        continue
      }
    fi

    _wire_one_module "${ext_name}" "${src_dir}" "${paths_json}"
    _setup_one_storage "${ext_name}" "${src_dir}" "${paths_json}"
    PROCESSED_NAMES+="${ext_name}"$'\n'
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
for name, entry in data.get('external_modules', {}).items():
    if not isinstance(entry, dict):
        continue  # boolean enable/disable flags are not module definitions
    url = entry.get('url', '')
    path = entry.get('path', '')
    paths = json.dumps(entry.get('paths', {}))
    print(f'{name}\x1f{url}\x1f{path}\x1f{paths}')
" 2>/dev/null || true)

  local disabled_json
  disabled_json=$(_devbot_get_disabled_modules "${PROJECT_DIR}")

  # External artifacts are wired into the devbot dir (.agents/) — harness-
  # agnostic, like the internal artifacts — so there is no opencode-specific
  # gate. A module's external agents/commands/skills are consumed by whichever
  # harness(es) are enabled via the delegation.

  # Single loop through agentic and tool modules — each iteration calls functions only
  for module_dir in "${DEV_BOT_ROOT}/src/agentic/"*/ "${DEV_BOT_ROOT}/src/tools/"*/; do
    _process_agentic_module "$(basename "${module_dir}")" "${disabled_json}"
  done

  # Config-only modules: entries registered directly in .devbot.global.jsonc
  # that no internal module declares (CLI/user-added git repos and local
  # paths). They are wired exactly like declared ones — a url entry is cloned
  # to vendor/ on first init, a local path is used as-is. Pruning (install.sh)
  # keeps this set free of leftovers, so wiring everything here is safe.
  local entry_line name url path paths_json
  while IFS= read -r entry_line; do
    [[ -z "${entry_line}" ]] && continue
    IFS=$'\x1f' read -r name url path paths_json <<< "${entry_line}"

    if [[ -z "${url}" && -z "${path}" ]]; then
      continue  # no source configured
    fi

    if echo "${PROCESSED_NAMES}" | grep -Fxq "${name}"; then
      continue  # already wired by the declared-module loop above
    fi

    if _is_disabled "${name}" "${disabled_json}"; then
      _skip "${name}: disabled — skipping"
      continue
    fi

    local src_dir
    if [[ -n "${path}" ]]; then
      if [[ ! -d "${path}" ]]; then
        _warn "${name}: local path not found (${path})"
        continue
      fi
      src_dir="${path}"
    else
      src_dir="${MODULES_DIR}/$(_derive_vendor_path "${url}")"
      if [[ ! -d "${src_dir}" ]]; then
        _install_one_module "${name}" "${url}" "${src_dir}" "${paths_json}" || {
          _warn "${name}: source not found at ${src_dir} — auto-install failed"
          continue
        }
      fi
    fi

    _wire_one_module "${name}" "${src_dir}" "${paths_json}"
    _setup_one_storage "${name}" "${src_dir}" "${paths_json}"
  done <<< "${MODULE_ENTRIES}"

  _ok "external-modules wiring complete"
}

main "$@"
