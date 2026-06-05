#!/usr/bin/env bash
# Update devbot CLI — refresh the symlink in case the binary changed.
# Same logic as install.sh but always relinks.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

main() {
  _info "devbot CLI"

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

main
