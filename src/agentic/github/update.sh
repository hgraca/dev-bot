#!/usr/bin/env bash
# Update GitHub CLI (gh) via system package manager.
# macOS: brew upgrade. Linux: dnf upgrade / apt upgrade.

set -euo pipefail

# shellcheck source=./functions.sh
source "$(dirname "$0")/functions.sh"

main() {
  _info "github"

  if ! command -v gh >/dev/null 2>&1; then
    echo "  ${TEXT_BOLD}${TEXT_YELLOW}⚠${TEXT_CLEAR}  gh not installed — re-run install." >&2
    exit 0
  fi

  case "$(uname -s)" in
    Darwin)
      _info "Updating gh via Homebrew..."
      brew upgrade gh 2>/dev/null || brew install gh 2>/dev/null
      ;;
    Linux)
      if command -v dnf >/dev/null 2>&1; then
        _info "Updating gh via dnf..."
        sudo dnf upgrade -y gh 2>/dev/null || true
      elif command -v apt-get >/dev/null 2>&1; then
        if sudo -n true 2>/dev/null; then
          _info "Updating gh via apt..."
          sudo apt-get update 2>/dev/null || true
          sudo apt-get install --only-upgrade -y gh
        else
          echo -e "  ${TEXT_BOLD}${TEXT_YELLOW}›${TEXT_CLEAR}  gh already installed (apt requires interactive sudo)." >&2
        fi
      fi
      ;;
  esac

  _ok "gh ($(gh --version | head -1))"
}

main
