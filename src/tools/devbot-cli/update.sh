#!/usr/bin/env bash
# Update devbot CLI — refresh the symlink in case the binary changed.
# Same logic as install.sh but always relinks.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# One-release bootstrap (remove in 1.16.0): the 1.14.0 updater predates both the
# versioned framework and the workspace migration, and it records 1.15.0 before
# the new reconciler rewrites the flat keys. This module already runs from the
# new checkout, so apply the 1.15.0 migrations here while the install still
# records an older version. They are idempotent, so later updates find nothing.
_bootstrap_config_migrations() {
  local migrations="${DEV_BOT_ROOT}/src/_shared/migrations.sh"
  local config
  config="$(_devbot_global_config)"
  [[ -f "${migrations}" && -f "${config}" ]] || return 0

  # shellcheck source=../../_shared/migrations.sh
  source "${migrations}"

  local recorded
  recorded="$(python3 "${DEV_BOT_ROOT}/src/_shared/read_jsonc.py" "${config}" version 2>/dev/null || true)"
  if [[ -n "${recorded}" ]] && _migration_valid_version "${recorded}" \
    && ! _migration_version_lt "${recorded}" "1.15.0"; then
    return 0
  fi

  local marker="${DEV_BOT_ROOT}/storage/run/migrate-bootstrap-pending"
  if migrate "${recorded:-0.0.0}" "1.15.0" "${config}"; then
    rm -f "${marker}"
    return 0
  fi
  # The pre-1.15 updater records the target even when a module fails, so leave
  # a marker the new updater retries from 0.0.0 instead of trusting the version.
  mkdir -p "${DEV_BOT_ROOT}/storage/run"
  touch "${marker}"
  return 1
}

main() {
  _info "devbot CLI"
  _bootstrap_config_migrations || _warn "config bootstrap needs attention — run devbot update again"

  local source="${DEV_BOT_ROOT}/bin/devbot"

  local target_dir=""
  if [[ -d "$HOME/.local/bin" ]] || mkdir -p "$HOME/.local/bin" 2>/dev/null; then
    target_dir="$HOME/.local/bin"
  elif [[ -d "/usr/local/bin" ]]; then
    target_dir="/usr/local/bin"
  else
    echo "  ${TEXT_BOLD}${TEXT_YELLOW}⚠${TEXT_CLEAR}  No suitable bin directory found." >&2
    exit 0
  fi

  local target="${target_dir}/devbot"
  rm -f "${target}"
  ln -s "${source}" "${target}"
  _ok "Re-linked ${target} -> ${source}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main
fi
