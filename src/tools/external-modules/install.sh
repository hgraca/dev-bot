#!/usr/bin/env bash
# Install external modules — clone/pull configured repos.
# Idempotent — skips if already at desired state.
#
# GATE: This module must work on Ubuntu, Fedora, and macOS.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../../_shared/functions.sh
source "${MODULE_DIR}/../../_shared/functions.sh"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

main() {
  _info "external-modules — install/update"

  local dev_bot_root
  dev_bot_root="$(cd "${MODULE_DIR}/../../.." && pwd)"
  local config_file="${dev_bot_root}/.devbot.global.jsonc"
  local modules_dir="${dev_bot_root}/vendor"

  # ── Rebuild external module config from declarations ──────────────────
  local disabled_raw
  disabled_raw=$(_devbot_get_disabled_modules)
  local disabled_modules
  disabled_modules=$(echo "${disabled_raw}" | jq -r '.[]' 2>/dev/null || true)

  local merge_script="${MODULE_DIR}/../../_shared/merge_modules_jsonc.py"
  local found_count=0
  local added_count=0

  for module_dir in "${dev_bot_root}/src/agentic/"*/; do
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

  if [[ ${found_count} -gt 0 ]]; then
    _ok "${found_count} module(s) with external module declarations processed (${added_count} with new entries added)"
  fi

  # Format .devbot.global.jsonc
  local format_json_tool="${dev_bot_root}/src/agentic/format-json/tools/format-json.mcp.sh"
  if [[ -f "${format_json_tool}" ]]; then
    bash "${format_json_tool}" "${config_file}" 2>/dev/null || true
  fi

  # Ensure config exists with external_modules key
  if [[ ! -f "${config_file}" ]]; then
    _skip ".devbot.global.jsonc not found — nothing to install/update"
    return 0
  fi

  # Read external modules configuration
  if ! python3 "${MODULE_DIR}/../../_shared/read_jsonc.py" "${config_file}" external_modules >/dev/null 2>&1; then
    _skip "No external modules configured in .devbot.global.jsonc"
    return 0
  fi

  # Process each module
  while IFS=$'\x1f' read -r name url local_path paths_json; do
    local src_dir=""
    if [[ -n "${local_path}" ]]; then
      # Local module - verify it exists
      if [[ ! -d "${local_path}" ]]; then
        _warn "${name}: local path not found (${local_path})"
        continue
      fi
      src_dir="${local_path}"
    elif [[ -n "${url}" ]]; then
      local vendor_rel dest
      vendor_rel="$(_derive_vendor_path "${url}")"
      dest="${modules_dir}/${vendor_rel}"
      _install_one_module "${name}" "${url}" "${dest}" "${paths_json}" || continue
      src_dir="${dest}"
    else
      _warn "${name}: missing url and local_path — skipping"
      continue
    fi

    _setup_external_module_storage "${src_dir}" "${name}" "${paths_json}" "${dev_bot_root}"
  done < <(python3 "${MODULE_DIR}/../../_shared/read_jsonc.py" "${config_file}" external_modules | \
    python3 -c "
import json, sys
data = json.load(sys.stdin)
for name, entry in data.items():
    if not isinstance(entry, dict):
        continue  # boolean enable/disable flags are not module definitions
    url = entry.get('url', '')
    local_path = entry.get('local_path', '')
    paths = json.dumps(entry.get('paths', {}))
    print(f'{name}\x1f{url}\x1f{local_path}\x1f{paths}')
  ")

  _ok "external-modules installation/update complete"
}

main
