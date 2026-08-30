#!/usr/bin/env bash
# =============================================================================
# bin/uninstall.sh
# Reverses the installation done by bin/install.sh:
#   1. Confirmation prompt (destructive action guard)
#   2. Runs each module's uninstall.sh (calls OS package manager to remove deps)
#   3. Removes .devbot.global.jsonc (with backup)
#   4. Prints summary of what was done
#
# Usage:
#   bin/uninstall.sh              # guided uninstall
#   SKIP_CONFIRM=1 bin/uninstall.sh   # non-interactive (for CI)
# =============================================================================

set -euo pipefail

# ── Resolve paths ─────────────────────────────────────────────────────────────
DEV_BOT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEV_BOT_ROOT

# ── Source shared library ──────────────────────────────────────────────────────
# shellcheck source=../src/_shared/functions.sh
source "${DEV_BOT_ROOT}/src/_shared/functions.sh"

# ── PATH ──────────────────────────────────────────────────────────────────────
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:/opt/homebrew/bin:/home/linuxbrew/.linuxbrew/bin:/usr/local/bin:$PATH"

# ── Confirmation guard ────────────────────────────────────────────────────────
_confirm() {
  _header_2 "Uninstall dev-bot"

  echo -e "  ${TEXT_YELLOW}This will:${TEXT_CLEAR}"
  echo "    • Remove OS-level dependencies installed by dev-bot modules"
  echo "    • Remove the .devbot.global.jsonc file (backed up as .devbot.global.jsonc.uninstall-backup)"
  echo "    • Remove the ~/.local/bin/devbot symlink, and the ~/.local/share/dev-bot bootstrap install dir (when present)"
  echo "    • NOT remove any files inside the repository itself"
  echo

  if [[ "${SKIP_CONFIRM:-0}" != "1" ]]; then
    echo -n "  Continue? [y/N] "
    read -r answer
    if [[ ! "${answer}" =~ ^[yY](es)?$ ]]; then
      echo
      _info "Uninstall cancelled."
      exit 0
    fi
  fi
}

# ── Config cleanup ──────────────────────────────────────────────────────────
_cleanup_config() {
  _header_2 "Config"

  if [[ -f "${DEV_BOT_ROOT}/.devbot.global.jsonc" ]]; then
    local backup="${DEV_BOT_ROOT}/.devbot.global.jsonc.uninstall-backup"
    _info "Backing up .devbot.global.jsonc to $(basename "${backup}")..."
    cp "${DEV_BOT_ROOT}/.devbot.global.jsonc" "${backup}"
    rm "${DEV_BOT_ROOT}/.devbot.global.jsonc"
    _ok ".devbot.global.jsonc removed (backup saved to $(basename "${backup}"))."
  else
    _ok "No .devbot.global.jsonc to remove."
  fi
}

# ── Bootstrap-install cleanup ─────────────────────────────────────────────────
# The direct-install bootstrap (root install.sh) installs to
# ~/.local/share/dev-bot and symlinks ~/.local/bin/devbot. Reverse both here:
# remove the symlink when it points at this root, and remove the bootstrap
# install directory entirely when uninstalling in place.
_cleanup_bootstrap() {
  local link="${HOME}/.local/bin/devbot"
  local target="${DEV_BOT_ROOT}/bin/devbot"

  if [[ -L "${link}" ]]; then
    local current
    current="$(readlink "${link}")"
    if [[ "${current}" == "${target}" ]]; then
      rm -f "${link}"
      _ok "removed ${link}"
    else
      _skip "${link} points elsewhere (${current}) — leaving it"
    fi
  elif [[ -e "${link}" ]]; then
    _warn "${link} exists and is not a symlink — leaving it"
  else
    _skip "no devbot symlink at ${link}"
  fi

  local bootstrap_dir="${HOME}/.local/share/dev-bot"
  if [[ "${DEV_BOT_ROOT}" == "${bootstrap_dir}" ]]; then
    _info "Removing bootstrap install directory ${bootstrap_dir}..."
    ( cd / && rm -rf "${bootstrap_dir}" )
    _ok "bootstrap install directory removed"
  fi
}

# ── Summary ────────────────────────────────────────────────────────────────────
print_summary() {
  _header_2 "✔  DevBot uninstall complete"

  echo -e "  ${TEXT_BOLD}Root    :${TEXT_CLEAR} ${DEV_BOT_ROOT}"
  echo -e "  ${TEXT_BOLD}Modules :${TEXT_CLEAR} ${MODULE_REMOVED:-0} uninstalled"
  echo -e "  ${TEXT_BOLD}Tools   :${TEXT_CLEAR} ${TOOL_REMOVED:-0} uninstalled"
  echo -e "  ${TEXT_BOLD}Harnesses :${TEXT_CLEAR} ${HARNESS_REMOVED:-0} uninstalled"
  echo
  echo -e "  ${TEXT_DIM}Repository left untouched.${TEXT_CLEAR}"
  echo
}

# ── main ──────────────────────────────────────────────────────────────────────
main() {
  local total_start=${SECONDS}
  local tool_count=0 module_count=0 harness_count=0

  _header_1 "DevBot Uninstall"

  _confirm

  _header_2 "Tools"
  _uninstall_modules "${DEV_BOT_ROOT}/src/tools"
  tool_count="${MODULE_SCRIPT_COUNT:-0}"

  _header_2 "Agentic Modules"
  _uninstall_modules "${DEV_BOT_ROOT}/src/agentic"
  module_count="${MODULE_SCRIPT_COUNT:-0}"

  _header_2 "Harnesses"
  _uninstall_modules "${DEV_BOT_ROOT}/src/harnesses"
  harness_count="${MODULE_SCRIPT_COUNT:-0}"

  _cleanup_config
  _cleanup_bootstrap
  TOOL_REMOVED="${tool_count}" MODULE_REMOVED="${module_count}" HARNESS_REMOVED="${harness_count}" print_summary

  echo -e "  ${TEXT_DIM}⏱  Total: $(_fmt_duration $(( SECONDS - total_start )))${TEXT_CLEAR}"
  echo
}

main "$@"
