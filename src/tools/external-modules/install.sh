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
  local config_file="${DEV_BOT_GLOBAL_CONFIG:-${DEV_BOT_ROOT}/.devbot.global.jsonc}"
  local modules_dir="${dev_bot_root}/vendor"

  # ── Rebuild external module config from declarations ──────────────────
  # Every module's declarations are merged regardless of enablement: the
  # config store and the vendor/ clones are global, shared by every project, so
  # a module disabled in one project must not deny its externals to the others.
  _devbot_rebuild_external_module_config

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

  # Process every configured entry. The config carries all declared modules
  # (enablement is not consulted), vendor/ is never pruned, and the storage
  # mirror is keyed off the same list — so removal happens only via
  # `devbot module remove`.
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
