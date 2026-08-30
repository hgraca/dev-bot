#!/usr/bin/env bash
# Install GitHub CLI (gh) — required by the gh-review command.
# macOS: installs via Homebrew. Linux: installs via dnf (Fedora) or apt (Debian/Ubuntu).
# Idempotent — skips if already installed.
#
# GATE: This module must work on Ubuntu, Fedora, and macOS.

set -euo pipefail

# shellcheck source=./functions.sh
source "$(dirname "$0")/functions.sh"

# GitHub CLI is not in the default Debian/Ubuntu repos — add the official
# GitHub CLI apt repository, then install gh.
_install_gh_apt() {
  sudo mkdir -p -m 755 /etc/apt/keyrings
  wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
  sudo apt-get update
  sudo apt-get install -y gh
}

main() {
  _info "github"

  if command -v gh >/dev/null 2>&1; then
    _skip "gh ($(gh --version | head -1 || echo 'installed'))"
  else
    case "$(uname -s)" in
      Darwin)
        _info "Installing gh via Homebrew..."
        brew install gh
        ;;
      Linux)
        if command -v dnf >/dev/null 2>&1; then
          _info "Installing gh via dnf..."
          sudo dnf install -y gh
        elif command -v apt-get >/dev/null 2>&1; then
          if ! command -v wget >/dev/null 2>&1; then
            _info "Installing wget (needed to fetch the GitHub CLI apt key)..."
            if ! sudo apt-get install -y wget >/dev/null 2>&1; then
              _fatal "Could not install wget (sudo apt-get install -y wget)."
              exit 1
            fi
          fi
          _info "Installing gh via apt (official GitHub CLI repo)..."
          _install_gh_apt
        else
          _fatal "No supported package manager found (dnf, apt-get). Install gh manually: https://github.com/cli/cli#installation"
          exit 1
        fi
        ;;
      *)
        _fatal "Unsupported OS: $(uname -s). Install gh manually: https://github.com/cli/cli#installation"
        exit 1
        ;;
    esac

    _ok "gh installed ($(gh --version | head -1))"
  fi
}

main
