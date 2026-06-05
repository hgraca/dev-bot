#!/usr/bin/env bash
# =============================================================================
# bin/init.sh
# Initialises dev-bot in a project directory. Sets up the agent vault
# and runs all init.sh scripts discovered under src/.
#
# Usage:
#   bin/init.sh                    # init in current directory
#   bin/init.sh /path/to/project   # init in specified project
#
# Adding a new init step:
#   Create src/tools/<module>/init.sh or src/agentic/<module>/init.sh — it will be auto-discovered and run.
# =============================================================================

set -euo pipefail

# ── Resolve paths ──────────────────────────────────────────────────────────────
DEV_BOT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEV_BOT_ROOT

# ── Source shared library ──────────────────────────────────────────────────────
# shellcheck source=../src/_shared/functions.sh
source "${DEV_BOT_ROOT}/src/_shared/functions.sh"

PROJECT_DIR="$(cd "${1:-$(pwd)}" && pwd 2>/dev/null || true)"

if [[ -z "${PROJECT_DIR}" || ! -d "${PROJECT_DIR}" ]]; then
  _error "Directory '${1:-.}' does not exist or cannot be resolved."
  exit 1
fi

PROJECT_NAME="$(basename "${PROJECT_DIR}")"

_register_module_mcp() {
  local mod_dir="$1"
  local config_file="$2"
  local config_name="$3"
  local gpu_enabled="$4"

  local mcp_file="${mod_dir}mcp.opencode.json"
  if [[ ! -f "${mcp_file}" || -z "${config_file}" ]]; then
    echo 0
    return
  fi

  local mod_name
  mod_name="$(basename "${mod_dir}")"
  local merge_mcp_script="${DEV_BOT_ROOT}/src/_shared/merge_mcp_jsonc.py"

  # Extract the MCP server key (top-level key in the JSON file)
  local mcp_key
  mcp_key=$(python3 -c "import json; print(list(json.load(open('${mcp_file}')).keys())[0])" 2>/dev/null || true)

  if [[ -z "${mcp_key}" ]]; then
    _warn "${mod_name}: could not parse MCP key from ${mcp_file} — skipping" >&2
    echo 0
    return
  fi

  # Check if already registered in config
  if grep -q "\"${mcp_key}\"" "${config_file}" 2>/dev/null; then
    _skip "${mod_name}: MCP '${mcp_key}' already registered in ${config_name}" >&2
    echo 0
    return
  fi

  _info "Registering ${mod_name} MCP '${mcp_key}' in ${config_name}..." >&2

  # Read the MCP server definition from the module's file
  local mcp_def
  mcp_def=$(python3 -c "import json; d=json.load(open('${mcp_file}')); print(json.dumps(d['${mcp_key}']))" 2>/dev/null || true)

  if [[ -z "${mcp_def}" ]]; then
    _warn "${mod_name}: could not read MCP definition from ${mcp_file} — skipping" >&2
    echo 0
    return
  fi

  # Substitute placeholders (e.g. __GPU_ENABLED__ → true/false boolean)
  mcp_def="${mcp_def//__GPU_ENABLED__/${gpu_enabled}}"

  # Merge into opencode config (comment-preserving approach)
  local merge_result
  merge_result=$(python3 "${merge_mcp_script}" "${config_file}" "${mcp_key}" "${mcp_def}" 2>/dev/null || true)
  case "${merge_result}" in
    INSERTED)
      _ok "${mod_name}: MCP '${mcp_key}' registered in ${config_name}" >&2
      echo 1
      ;;
    SKIP_EXISTS)
      _skip "${mod_name}: MCP '${mcp_key}' already registered in ${config_name}" >&2
      echo 0
      ;;
    *)
      _error "${mod_name}: merge_mcp_jsonc returned unexpected result '${merge_result}' — skipping" >&2
      echo 0
      ;;
  esac
}

_link_module_memory() {
  local mod_dir="$1"
  local memory_dir="$2"
  local mod_name
  mod_name="$(basename "${mod_dir}")"

  local mem_dir="${mod_dir}memory"
  [[ -d "${mem_dir}" ]] || return 0

  local link_path="${memory_dir}/${mod_name}"
  mkdir -p "${memory_dir}"

  if [[ -L "${link_path}" ]]; then
    local current
    current="$(readlink "${link_path}")"
    if [[ "${current}" == "${mem_dir}" ]]; then
      _skip "${mod_name} memory → ${mem_dir} (already linked)"
    else
      rm "${link_path}"
      ln -s "${mem_dir}" "${link_path}"
      _log "${mod_name} memory → ${mem_dir} (repaired)"
    fi
  elif [[ -e "${link_path}" ]]; then
    _warn "${link_path} exists but is not a symlink — skipping"
  else
    ln -s "${mem_dir}" "${link_path}"
    _log "${mod_name} memory → ${mem_dir}"
  fi
}

_run_external_module_init() {
  local ext_mod_dir="$1"
  local project_dir="$2"
  local ext_init="${ext_mod_dir}init.sh"
  [[ -f "${ext_init}" ]] || return 1

  local ext_mod_name
  ext_mod_name="$(basename "${ext_mod_dir}")"
  _header_3 "Running ${ext_mod_name} init..."
  local start=${SECONDS}
  if bash "${ext_init}" "${project_dir}"; then
    _ok "${ext_mod_name} init done ($(_fmt_duration $(( SECONDS - start ))))"
  else
    _warn "${ext_mod_name} init had issues"
  fi
}

_link_external_module_memory() {
  local ext_mod_dir="$1"
  local memory_dir="$2"
  local ext_mem_dir="${ext_mod_dir}memory"
  [[ -d "${ext_mem_dir}" ]] || return 0

  local ext_mod_name
  ext_mod_name="$(basename "${ext_mod_dir}")"

  _step "${ext_mod_name}: linking memory files..."

  while IFS= read -r -d '' file; do
    local rel_path="${file#"${ext_mem_dir}"/}"
    local target_link="${memory_dir}/${rel_path}"
    local target_dir
    target_dir="$(dirname "${target_link}")"

    mkdir -p "${target_dir}"

    if [[ -L "${target_link}" ]]; then
      local current_target
      current_target="$(readlink "${target_link}")"
      if [[ -L "${file}" ]]; then
        local desired_target
        desired_target="$(readlink "${file}")"
        if [[ "${current_target}" == "${desired_target}" ]]; then
          _skip "${ext_mod_name} memory → ${rel_path} (already correct)"
          continue
        fi
      fi
      rm "${target_link}"
      # fall through to recreate
    elif [[ -e "${target_link}" ]]; then
      _warn "${target_link} exists but is not a symlink — skipping"
      continue
    fi

    # Create symlink pointing to the same vendor file
    if [[ -L "${file}" ]]; then
      local vendor_target
      vendor_target="$(readlink "${file}")"
      ln -s "${vendor_target}" "${target_link}"
    else
      ln -s "${file}" "${target_link}"
    fi
    _log "${ext_mod_name} memory → ${rel_path}"
  done < <(find "${ext_mem_dir}" \( -type f -o -type l \) -print0)
}

# ── Test-compatible entry points ───────────────────────────────────────────────
#
# _run_inits — runs init.sh for each external agentic module.
# Called by tests and by main().

_run_inits() {
  local external_base="${DEV_BOT_ROOT}/storage/external-agentic-modules"
  [[ -d "${external_base}" ]] || return 0

  local disabled_list
  disabled_list=$(echo "$(_devbot_get_disabled_modules "${PROJECT_DIR}")" | python3 -c "
import json, sys
for m in json.loads(sys.stdin.read()):
    print(m)
" 2>/dev/null || true)

  for ext_mod_dir in "${external_base}/"*/; do
    local ext_mod_name
    ext_mod_name="$(basename "${ext_mod_dir}")"

    if echo "${disabled_list}" | grep -Fxq "${ext_mod_name}" 2>/dev/null; then
      _skip "${ext_mod_name}: disabled per config — skipping"
      continue
    fi

    _run_external_module_init "${ext_mod_dir}" "${PROJECT_DIR}" || true
  done
}

# _link_memory_folders — links memory for built-in + external modules.
# Idempotent. Called by tests and by main().
# Gitignore is handled by the memory module (src/agentic/memory/init.sh).

_link_memory_folders() {
  local memory_dir="${PROJECT_DIR}/$(_devbot_get_project_dir "${PROJECT_DIR}")/memory"

  local disabled_list
  disabled_list=$(echo "$(_devbot_get_disabled_modules "${PROJECT_DIR}")" | python3 -c "
import json, sys
for m in json.loads(sys.stdin.read()):
    print(m)
" 2>/dev/null || true)

  # Built-in modules (tools + agentic + harnesses)
  for base_dir in "${DEV_BOT_ROOT}/src/tools" "${DEV_BOT_ROOT}/src/agentic" "${DEV_BOT_ROOT}/src/harnesses"; do
    for mod_dir in "${base_dir}/"*/; do
      local mod_name
      mod_name="$(basename "${mod_dir}")"
      if echo "${disabled_list}" | grep -Fxq "${mod_name}" 2>/dev/null; then
        continue
      fi
      _link_module_memory "${mod_dir}" "${memory_dir}"
    done
  done

  # External modules
  local external_base="${DEV_BOT_ROOT}/storage/external-agentic-modules"
  if [[ -d "${external_base}" ]]; then
    for ext_mod_dir in "${external_base}/"*/; do
      local ext_mod_name
      ext_mod_name="$(basename "${ext_mod_dir}")"
      if echo "${disabled_list}" | grep -Fxq "${ext_mod_name}" 2>/dev/null; then
        continue
      fi
      _link_external_module_memory "${ext_mod_dir}" "${memory_dir}"
    done
  fi
}

# ── main ───────────────────────────────────────────────────────────────────────
_format_opencode_config() {
  local config="${PROJECT_DIR}/opencode.jsonc"
  [[ -f "${config}" ]] || return 0

  local fmt_tool="${DEV_BOT_ROOT}/src/agentic/format-json/tools/format-json.sh"
  if [[ -x "${fmt_tool}" ]]; then
    bash "${fmt_tool}" "${config}" 2>/dev/null && _ok "opencode.jsonc formatted" || true
  fi
}

main() {
  local total_start=${SECONDS}

  _header_1 "DevBot Init"

  # ── Parse disabled modules ONCE ────────────────────────────────────────────
  local disabled_modules_raw
  disabled_modules_raw=$(_devbot_get_disabled_modules "${PROJECT_DIR}")
  local disabled_modules
  disabled_modules=$(echo "${disabled_modules_raw}" | python3 -c "
import json, sys
modules = json.loads(sys.stdin.read())
for m in modules:
    print(m)
" 2>/dev/null || true)

  local gpu_enabled
  gpu_enabled="$(_devbot_get_bool "gpu_enabled")"

  # ── Shared paths ──────────────────────────────────────────────────────────
  local devbot_dir
  devbot_dir="$(_devbot_get_project_dir "${PROJECT_DIR}")"
  local memory_dir="${PROJECT_DIR}/${devbot_dir}/memory"

  # ── Migration: move old .ai/devbot to .agents ────────────────────────────
  _migrate_legacy_state() {
    local old_devbot="${PROJECT_DIR}/.ai/devbot"
    local new_devbot="${PROJECT_DIR}/${devbot_dir}"

    if [[ ! -d "${old_devbot}" ]]; then
      return 0
    fi

    # Migrate memory
    local old_memory="${old_devbot}/memory"
    local new_memory="${new_devbot}/memory"
    if [[ -d "${old_memory}" && ! -d "${new_memory}" ]]; then
      _step "Migrating memory from .ai/devbot/memory to ${devbot_dir}/memory..."
      mkdir -p "$(dirname "${new_memory}")"
      mv "${old_memory}" "${new_memory}" 2>/dev/null || {
        _warn "Could not move memory — copying instead"
        cp -r "${old_memory}" "${new_memory}" 2>/dev/null || true
      }
      _ok "Memory migrated to ${devbot_dir}/memory"
    fi

    # Migrate logs
    local old_logs="${old_devbot}/logs"
    local new_logs="${new_devbot}/logs"
    if [[ -d "${old_logs}" && ! -d "${new_logs}" ]]; then
      _step "Migrating logs from .ai/devbot/logs to ${devbot_dir}/logs..."
      mkdir -p "$(dirname "${new_logs}")"
      mv "${old_logs}" "${new_logs}" 2>/dev/null || {
        _warn "Could not move logs — copying instead"
        cp -r "${old_logs}" "${new_logs}" 2>/dev/null || true
      }
      _ok "Logs migrated to ${devbot_dir}/logs"
    fi

    # Remove old devbot dir if empty
    rmdir "${old_devbot}" 2>/dev/null || true
  }
  _migrate_legacy_state

  # ── Migration: rename bootstrap/ → active/ ──────────────────────────────
  if [[ -d "${memory_dir}/bootstrap" && ! -d "${memory_dir}/active" ]]; then
    _step "Renaming memory/bootstrap to memory/active..."
    mv "${memory_dir}/bootstrap" "${memory_dir}/active"
    _ok "Renamed to memory/active"
  fi

  # Detect opencode config (prefer jsonc, fall back to json)
  local config_file=""
  local config_name=""
  if [[ -f "${PROJECT_DIR}/opencode.jsonc" ]]; then
    config_file="${PROJECT_DIR}/opencode.jsonc"
    config_name="opencode.jsonc"
  elif [[ -f "${PROJECT_DIR}/opencode.json" ]]; then
    config_file="${PROJECT_DIR}/opencode.json"
    config_name="opencode.json"
  fi

  # ── 2. Init scripts (tools + agentic) ────────────────────────────────────
  _header_2 "Init Scripts"

  _init_modules "${DEV_BOT_ROOT}/src/tools" "${PROJECT_DIR}"

  # Re-parse disabled_modules — tool init may have created/modified project config
  disabled_modules_raw=$(_devbot_get_disabled_modules "${PROJECT_DIR}")
  disabled_modules=$(echo "${disabled_modules_raw}" | python3 -c "
import json, sys
modules = json.loads(sys.stdin.read())
for m in modules:
    print(m)
" 2>/dev/null || true)

  # Re-detect config_file — tool-init may have created opencode.jsonc
  if [[ -z "${config_file}" && -f "${PROJECT_DIR}/opencode.jsonc" ]]; then
    config_file="${PROJECT_DIR}/opencode.jsonc"
    config_name="opencode.jsonc"
  fi

  _header_2 "Agentic Modules"
  _init_modules "${DEV_BOT_ROOT}/src/agentic" "${PROJECT_DIR}"

  _header_2 "Harnesses"
  _init_modules "${DEV_BOT_ROOT}/src/harnesses" "${PROJECT_DIR}"

  # ── 3. MCP registration (unified — tools + agentic + harnesses) ────────
  local mcp_count=0

  for base_dir in "${DEV_BOT_ROOT}/src/tools" "${DEV_BOT_ROOT}/src/agentic" "${DEV_BOT_ROOT}/src/harnesses"; do
    for mod_dir in "${base_dir}/"*/; do
      local mod_name
      mod_name="$(basename "${mod_dir}")"

      if echo "${disabled_modules}" | grep -Fxq "${mod_name}" 2>/dev/null; then
        continue
      fi

      mcp_count=$((mcp_count + $(_register_module_mcp "${mod_dir}" "${config_file}" "${config_name}" "${gpu_enabled}")))
    done
  done

  # ── 4. Memory links + external module init ──────────────────────────────
  _link_memory_folders

  _header_2 "External Agentic Modules"
  _run_inits

  # ── 6. MCP summary ──────────────────────────────────────────────────────
  if [[ ${mcp_count} -gt 0 ]]; then
    _info "${mcp_count} MCP server(s) registered — restart opencode for changes to take effect"
    _format_opencode_config
  fi

  # ── 7. Register project in global config ────────────────────────────────
  local add_project_py="${DEV_BOT_ROOT}/src/_shared/add_project.py"
  local global_config="${DEV_BOT_ROOT}/.devbot.global.jsonc"
  if [[ -f "${add_project_py}" && -f "${global_config}" ]]; then
    python3 "${add_project_py}" "${global_config}" "${PROJECT_DIR}" 2>/dev/null || true
  fi

  # ── 8. Final header ─────────────────────────────────────────────────────
  _header_2 "✔  DevBot init complete, you still should run the '/create-codebase-report' command on the first time you start the agent"

  echo -e "  ${TEXT_DIM}⏱  Total: $(_fmt_duration $(( SECONDS - total_start )))${TEXT_CLEAR}"
  echo
}

main "$@"
