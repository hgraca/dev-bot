#!/usr/bin/env bash
# Update tree — reinstall via system package manager.
# macOS: brew upgrade. Linux: apt upgrade / dnf upgrade.

set -euo pipefail

# shellcheck source=./functions.sh
source "$(dirname "$0")/functions.sh"

main() {
  _info "tree"

  if ! command -v tree &>/dev/null; then
    echo "  ${TEXT_BOLD}${TEXT_YELLOW}⚠${TEXT_CLEAR}  tree not installed — re-run install." >&2
    exit 0
  fi

  case "$(uname -s)" in
    Darwin)
      _info "Updating tree via Homebrew..."
      brew upgrade tree 2>/dev/null || brew install tree 2>/dev/null
      ;;
    Linux)
      if command -v dnf &>/dev/null; then
        _info "Updating tree via dnf..."
        sudo dnf upgrade -y tree 2>/dev/null || true
      elif command -v apt-get &>/dev/null; then
        if sudo -n true 2>/dev/null; then
          _info "Updating tree via apt..."
          sudo apt-get install --only-upgrade -y tree
        else
          echo -e "  ${TEXT_BOLD}${TEXT_YELLOW}›${TEXT_CLEAR}  tree already installed (apt requires interactive sudo)." >&2
        fi
      fi
      ;;
  esac

  _ok "tree ($(tree --version 2>/dev/null | head -1))"
}

main
