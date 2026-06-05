#!/usr/bin/env bash
# =============================================================================
# src/tools/opencode/init.sh
# Sets up opencode in a project: copies the .opencode/ template directory,
# writes opencode.jsonc from the dist template, creates symlinks for agents,
# commands, skills, tools, and plugins, and removes .gitkeep files.
#
# Usage:
#   init.sh                    # init in current directory
#   init.sh /path/to/project   # init in specified project
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

PROJECT_DIR="$(cd "${1:-$(pwd)}" && pwd 2>/dev/null || true)"

if [[ -z "${PROJECT_DIR}" || ! -d "${PROJECT_DIR}" ]]; then
  echo "Error: directory '${1:-.}' does not exist or cannot be resolved." >&2
  exit 1
fi

# shellcheck source=../_shared/functions.sh
source "${DEV_BOT_ROOT}/src/_shared/functions.sh"

# ── Paths ──────────────────────────────────────────────────────────────────────

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "${MODULE_DIR}/../../.." && pwd)}"
OPENCODE_TPL="${MODULE_DIR}/_opencode.tpl"
DIST_CONFIG="${MODULE_DIR}/opencode.dist.jsonc"
OPENCODE_DIR="${PROJECT_DIR}/.opencode"

# ── Merge .opencode/ template directory ───────────────────────────────────────
_copy_opencode_dir() {
  if [[ ! -d "${OPENCODE_TPL}" ]]; then
    _warn "Template directory not found at ${OPENCODE_TPL}"
    return 1
  fi

  local copied=0
  mkdir -p "${OPENCODE_DIR}"

  while IFS= read -r -d '' src_file; do
    local rel="${src_file#${OPENCODE_TPL}/}"
    local tgt="${OPENCODE_DIR}/${rel}"

    [[ "$(basename "${rel}")" == ".gitkeep" ]] && return

    if [[ -e "${tgt}" ]]; then
      _skip "${rel} already exists"
    else
      mkdir -p "$(dirname "${tgt}")"
      cp -r "${src_file}" "${tgt}"
      _ok "${rel} copied"
      copied=$((copied + 1))
    fi
  done < <(find "${OPENCODE_TPL}" -mindepth 1 -print0 2>/dev/null | sort -z)

  if [[ ${copied} -eq 0 ]]; then
    _skip "no new files from template"
  fi
}

# ── Remove .gitkeep files ──────────────────────────────────────────────────────
_remove_gitkeep_files() {
  local count=0
  while IFS= read -r -d '' f; do
    rm -f "$f"
    count=$((count + 1))
  done < <(find "${OPENCODE_DIR}" -name '.gitkeep' -type f -print0 2>/dev/null)
  if [[ ${count} -gt 0 ]]; then _ok "Removed ${count} .gitkeep file(s) from .opencode/"; fi
}

# ── Link plugins ───────────────────────────────────────────────────────────────
_link_plugins() {
  local mod_dir="$1"
  local hook_dir="${mod_dir}hooks/opencode"
  [[ ! -d "${hook_dir}" ]] && return
  local mod_name
  mod_name="$(basename "${mod_dir}")"

  while IFS= read -r -d '' plugin_file; do
    local plugin_name
    plugin_name="$(basename "${plugin_file}")"
    local target="${plugin_file}"
    local link="${OPENCODE_DIR}/plugins/${plugin_name}"

    if [[ -L "${link}" ]]; then
      local current
      current="$(readlink "${link}")"
      if [[ "${current}" == "${target}" ]]; then
        _skip "plugins/${plugin_name} already linked"
        _upsert_opencode_plugin "${PROJECT_DIR}/opencode.jsonc" ".opencode/plugins/${plugin_name}"
      else
        rm -f "${link}"
        ln -sf "${target}" "${link}"
        _ok "plugins/${plugin_name} relinked"
        _upsert_opencode_plugin "${PROJECT_DIR}/opencode.jsonc" ".opencode/plugins/${plugin_name}"
      fi
    elif [[ -e "${link}" ]]; then
      _warn "plugins/${plugin_name} exists but is not a symlink"
    else
      mkdir -p "$(dirname "${link}")"
      ln -sf "${target}" "${link}"
      _ok "plugins/${plugin_name} linked"
      _upsert_opencode_plugin "${PROJECT_DIR}/opencode.jsonc" ".opencode/plugins/${plugin_name}"
    fi
  done < <(find "${hook_dir}" -maxdepth 1 -type f -print0 2>/dev/null)
}

# ── Write opencode.jsonc from template ─────────────────────────────────────────
_write_opencode_config() {
  local config="${PROJECT_DIR}/opencode.jsonc"

  if [[ -f "${config}" ]]; then
    _skip "opencode.jsonc already exists"
    return 0
  fi

  if [[ ! -f "${DIST_CONFIG}" ]]; then
    _warn "Template not found at ${DIST_CONFIG}"
    return 1
  fi

  _info "Writing opencode.jsonc..."

  # Read gpu_enabled from .devbot.global.jsonc
  local gpu_enabled="false"
  gpu_enabled="$(_devbot_get_bool "gpu_enabled")"

  sed "s|__QMD_LLAMA_GPU__|${gpu_enabled}|g" "${DIST_CONFIG}" > "${config}"
  _ok "opencode.jsonc written"
}

_link_plugins_modules() {
  # Resolve disabled modules
  local disabled_raw
  disabled_raw=$(_devbot_get_disabled_modules "${PROJECT_DIR}")
  local disabled_modules
  disabled_modules=$(echo "${disabled_raw}" | python3 -c "
import json, sys
modules = json.loads(sys.stdin.read())
for m in modules:
    print(m)
" 2>/dev/null || true)

  for mod_dir in "${DEV_BOT_ROOT}/src/agentic/"*/; do
    local mod_name
    mod_name="$(basename "${mod_dir}")"

    # Skip ENTIRE module if disabled — no symlinks created
    if echo "${disabled_modules}" | grep -Fxq "${mod_name}" 2>/dev/null; then
      _skip "${mod_name}: disabled per config — skipping"
      continue
    fi

    _link_plugins "${mod_dir}"
  done
}

# ── main ───────────────────────────────────────────────────────────────────────
_copy_opencode_dir
_write_opencode_config
_harness_delegate_to_agents "${OPENCODE_DIR}" "${PROJECT_DIR}"
_link_plugins_modules
_remove_gitkeep_files
