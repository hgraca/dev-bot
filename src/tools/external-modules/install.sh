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

  # DEV_BOT_ROOT/CONFIG_FILE/MODULES_DIR may be pre-set (tests run against a sandbox).
  local dev_bot_root="${DEV_BOT_ROOT:-$(cd "${MODULE_DIR}/../../.." && pwd)}"
  local config_file="${CONFIG_FILE:-${dev_bot_root}/.devbot.global.jsonc}"
  local modules_dir="${MODULES_DIR:-${dev_bot_root}/vendor}"

  # ── Rebuild external module config from declarations ──────────────────
  local disabled_raw
  disabled_raw=$(_devbot_get_disabled_modules)
  local disabled_modules
  disabled_modules=$(echo "${disabled_raw}" | jq -r '.[]' 2>/dev/null || true)

  local merge_script="${MODULE_DIR}/../../_shared/merge_modules_jsonc.py"
  local found_count=0
  local added_count=0
  local updated_count=0

  # Scan declarations from both agentic and tool modules (mirrors bin/up.sh).
  for module_dir in "${dev_bot_root}/src/agentic/"*/ "${dev_bot_root}/src/tools/"*/; do
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

    # Insert missing entries, then propagate declaration changes (url/paths)
    # onto existing ones — user-added keys such as a local `path` are preserved
    # by the --update mode. --owner records provenance on both.
    local insert_result update_result
    insert_result=$(python3 "${merge_script}" "${config_file}" "${ext_file}" --owner "${module_name}" 2>&1) || true
    update_result=$(python3 "${merge_script}" "${config_file}" --update "${ext_file}" --owner "${module_name}" 2>&1) || true

    if echo "${insert_result}" | grep -q "^INSERTED"; then
      _log "${module_name}: ${insert_result}"
      added_count=$((added_count + 1))
    else
      _skip "${module_name}: ${insert_result}"
    fi

    if echo "${update_result}" | grep -q "^UPDATED"; then
      _log "${module_name}: ${update_result}"
      updated_count=$((updated_count + 1))
    fi
  done

  if [[ ${found_count} -gt 0 ]]; then
    _ok "${found_count} module(s) with external module declarations processed (${added_count} new, ${updated_count} updated)"
  fi

  # Prune stale config entries left behind by disabled modules (before the
  # processing loop below, so they are not cloned/storage-set this run).
  _prune_stale_external_modules "${config_file}" "${dev_bot_root}" "${disabled_raw}" "${merge_script}"

  # Format .devbot.global.jsonc — after the merge/prune writes, so the file is
  # left in canonical shape.
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

  # Process the module graph to closure — source is either a git url (cloned
  # to vendor/) or a local path (wired directly, never cloned). Each external
  # module's root may declare further external modules (external-modules.json);
  # those are merged and processed in the next round until nothing new appears.
  # A visited set plus the merge's add-only insert make cycles terminate.
  local processed=""
  local round=0
  while [[ ${round} -lt 50 ]]; do
    local changed=0
    round=$((round + 1))

    while IFS=$'\x1f' read -r name url path paths_json; do
      if echo "${processed}" | grep -Fxq "${name}"; then
        continue
      fi

      local src_dir=""
      if [[ -n "${path}" ]]; then
        # Local module - verify it exists
        if [[ ! -d "${path}" ]]; then
          _warn "${name}: local path not found (${path})"
          processed+="${name}"$'\n'
          continue
        fi
        src_dir="${path}"
      elif [[ -n "${url}" ]]; then
        local vendor_rel dest
        vendor_rel="$(_derive_vendor_path "${url}")"
        dest="${modules_dir}/${vendor_rel}"
        _install_one_module "${name}" "${url}" "${dest}" "${paths_json}" || {
          processed+="${name}"$'\n'  # do not retry a failing clone every round
          continue
        }
        src_dir="${dest}"
      else
        _warn "${name}: missing url and path — skipping"
        processed+="${name}"$'\n'
        continue
      fi

      # Transitive declarations from this module's own root.
      local ext_file="${src_dir}/external-modules.json"
      if [[ -f "${ext_file}" ]]; then
        local decl_result
        decl_result=$(python3 "${merge_script}" "${config_file}" "${ext_file}" --owner "${name}" 2>&1) || true
        if echo "${decl_result}" | grep -q "^INSERTED"; then
          changed=1
          _log "${name}: transitively declared ${decl_result}"
        fi
        python3 "${merge_script}" "${config_file}" --update "${ext_file}" --owner "${name}" >/dev/null 2>&1 || true
      fi

      _setup_external_module_storage "${src_dir}" "${name}" "${paths_json}" "${dev_bot_root}"
      processed+="${name}"$'\n'
    done < <(python3 "${MODULE_DIR}/../../_shared/read_jsonc.py" "${config_file}" external_modules | \
      python3 -c "
import json, sys
data = json.load(sys.stdin)
for name, entry in data.items():
    if not isinstance(entry, dict):
        continue  # boolean enable/disable flags are not module definitions
    url = entry.get('url', '')
    path = entry.get('path', '')
    paths = json.dumps(entry.get('paths', {}))
    print(f'{name}\x1f{url}\x1f{path}\x1f{paths}')
  ")

    [[ ${changed} -eq 0 ]] && break
  done

  # Prune stale vendor clones no longer referenced by the config.
  _prune_stale_vendor_clones "${modules_dir}" "${config_file}"

  _ok "external-modules installation/update complete"
}

main
