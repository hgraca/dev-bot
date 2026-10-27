#!/usr/bin/env bash
# Install external modules — clone/pull configured repos and render their
# mirrors.
#
# One implementation with `devbot module install`: both call
# _external_module_install_all, so the validated update path (a configured path
# that vanished upstream cancels that module's update and keeps its legacy
# checkout) applies to `devbot install`, `devbot update` and the CLI alike.
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

  # DEV_BOT_ROOT is set by bin/install.sh and bin/update.sh; honour it so the
  # script also works from a sandbox/test root, and fall back to this checkout.
  # It must be EXPORTED: the shared helpers resolve their root from the
  # environment, not from a local.
  local dev_bot_root
  dev_bot_root="${DEV_BOT_ROOT:-$(cd "${MODULE_DIR}/../../.." && pwd)}"
  export DEV_BOT_ROOT="${dev_bot_root}"
  local config_file="${DEV_BOT_GLOBAL_CONFIG:-${dev_bot_root}/.devbot.global.jsonc}"

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
  if ! _external_module_install_all "${config_file}" "${dev_bot_root}"; then
    _error "external modules: some modules were not installed/updated — see the errors above"
    return 1
  fi

  _ok "external-modules installation/update complete"
}

main
