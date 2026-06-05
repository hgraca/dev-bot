#!/usr/bin/env bash
# Install tree — directory listing utility used by the tree-report tool.
# macOS: installs via Homebrew. Linux: installs via apt (Debian/Ubuntu) or dnf (Fedora).
# Idempotent — skips if already installed.

set -euo pipefail

# shellcheck source=./functions.sh
source "$(dirname "$0")/functions.sh"

# ── Colors (inline — no shared library dependency) ─────────────────────────────
main() {
  _info "tree"

  if command -v tree &>/dev/null; then
    _skip "tree ($(tree --version 2>/dev/null | head -1 || echo 'installed'))"
    exit 0
  fi

  case "$(uname -s)" in
    Darwin)
      _info "Installing tree via Homebrew..."
      brew install tree
      ;;
    Linux)
      if command -v dnf &>/dev/null; then
        _info "Installing tree via dnf..."
        sudo dnf install -y tree
      elif command -v apt-get &>/dev/null; then
        _info "Installing tree via apt..."
        sudo apt-get install -y tree
      else
        echo "  ${TEXT_BOLD}${TEXT_YELLOW}⚠${TEXT_CLEAR}  No supported package manager found (dnf, apt-get). Install tree manually." >&2
        exit 1
      fi
      ;;
    *)
      echo "  ${TEXT_BOLD}${TEXT_RED}✘${TEXT_CLEAR}  Unsupported OS: $(uname -s). Install tree manually." >&2
      exit 1
      ;;
  esac

  _ok "tree installed ($(tree --version 2>/dev/null | head -1))"
}

main
