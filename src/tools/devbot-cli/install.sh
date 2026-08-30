#!/usr/bin/env bash
# Install devbot CLI — symlinks bin/devbot into a system PATH location
# so it can be run from anywhere.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"

main() {
  _info "devbot CLI"

  local source="${DEV_BOT_ROOT}/bin/devbot"

  # Choose the best target directory
  local target_dir=""
  local target=""

  # Prefer ~/.local/bin (already in the exported PATH), then /usr/local/bin
  if [[ -d "$HOME/.local/bin" ]] || mkdir -p "$HOME/.local/bin" 2>/dev/null; then
    target_dir="$HOME/.local/bin"
  elif [[ -d "/usr/local/bin" ]]; then
    target_dir="/usr/local/bin"
  else
    echo "  ${TEXT_BOLD}${TEXT_YELLOW}⚠${TEXT_CLEAR}  No suitable bin directory found for symlink." >&2
    echo "  ${TEXT_BOLD}${TEXT_YELLOW}⚠${TEXT_CLEAR}  Add ${source} to your PATH manually." >&2
    exit 0
  fi

  target="${target_dir}/devbot"

  # ── Link the CLI (guarded — idempotent) ─────────────────────────────────
  # The guard only wraps the link step; lifecycle steps below (bash completion)
  # must run on every invocation, including re-installs.
  if [[ -L "${target}" ]] && [[ "$(readlink "${target}")" == "${source}" ]]; then
    _skip "devbot already linked (${target} -> ${source})"
  else
    # Remove existing file/symlink if it points elsewhere
    if [[ -e "${target}" ]] || [[ -L "${target}" ]]; then
      rm -f "${target}"
    fi

    ln -s "${source}" "${target}"
    _ok "Linked ${target} -> ${source}"
  fi

  # ── Install bash completion ────────────────────────────────────────────────
  # Runs unconditionally so re-installs refresh the completion link.
  local completion_source="${DEV_BOT_ROOT}/src/tools/devbot-cli/completion.sh"
  local completion_target="${HOME}/.local/share/bash-completion/completions/devbot"

  if command -v bash >/dev/null 2>&1; then
    mkdir -p "$(dirname "${completion_target}")"
    if [[ -f "${completion_source}" ]]; then
      if [[ -L "${completion_target}" ]] && [[ "$(readlink "${completion_target}")" == "${completion_source}" ]]; then
        _skip "completion already linked (${completion_target})"
      else
        rm -f "${completion_target}"
        ln -s "${completion_source}" "${completion_target}"
        _ok "Completion linked ${completion_target}"
      fi
    fi
  fi
}

main
