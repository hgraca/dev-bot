#!/usr/bin/env bash
# ghostty module helpers — install the terminal, and tell the user how to make
# it the default one.
#
# Installation is the only thing scripted: making a terminal the system default
# stays the user's call, so both install and update print the command instead of
# running it.

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_shared/functions.sh
source "${MODULE_DIR}/../../_shared/functions.sh"

GHOSTTY_INSTALL_DOCS="https://ghostty.org/docs/install/binary"

# Installed means the binary is on PATH, or — on macOS, where the documented
# route is dragging the .dmg into Applications — the app bundle exists. The brew
# cask is only one of the ways in, and a cask-only probe turns a .dmg install
# into a failing `brew install` on every run.
_ghostty_installed() {
  command -v ghostty >/dev/null 2>&1 && return 0
  [[ -d "/Applications/Ghostty.app" ]]
}

_ghostty_cask_installed() {
  command -v brew >/dev/null 2>&1 && brew list --cask ghostty >/dev/null 2>&1
}

# ubuntu | debian | other — what the Linux package route can actually be. The
# community PPA this module uses publishes Ubuntu suites only, so a Debian or
# Fedora machine must not be sent at it.
_ghostty_linux_family() {
  # The path is a seam for the tests (and for inspecting another rootfs); the
  # value it reads is the distribution's own.
  local osr="${GHOSTTY_OS_RELEASE:-/etc/os-release}" id="" like=""
  if [[ -r "${osr}" ]]; then
    id="$(sed -n 's/^ID=//p' "${osr}" 2>/dev/null | tr -d '"' | head -1)"
    like="$(sed -n 's/^ID_LIKE=//p' "${osr}" 2>/dev/null | tr -d '"' | head -1)"
  fi
  if [[ "${like} ${id}" == *ubuntu* ]]; then
    printf 'ubuntu'
    return 0
  fi
  if [[ "${like} ${id}" == *debian* ]]; then
    printf 'debian'
    return 0
  fi
  # No os-release at all: fall back to the package manager that is there. A file
  # that names a foreign distribution is answered by that name, never by apt
  # happening to be installed alongside it.
  if [[ -z "${id}" && -z "${like}" ]] && command -v apt-get >/dev/null 2>&1; then
    printf 'ubuntu'
    return 0
  fi
  printf 'other'
}

# _ghostty_install [interactive]
#   interactive=1 (a human ran `devbot install`) lets sudo prompt; the unattended
#   path (`devbot update --auto` at session start) only uses `sudo -n` and warns
#   instead of blocking on a password nobody is there to type.
_ghostty_install() {
  local interactive="${1:-1}"
  case "$(uname -s)" in
    Darwin) _ghostty_install_brew ;;
    Linux) _ghostty_install_linux "${interactive}" ;;
    *)
      _warn "unsupported OS $(uname -s) — install ghostty by hand: ${GHOSTTY_INSTALL_DOCS}"
      ;;
  esac
}

_ghostty_install_brew() {
  if _ghostty_installed; then
    _skip "ghostty already installed"
    if ! _ghostty_cask_installed; then
      _info "installed outside Homebrew — 'brew install --cask ghostty --adopt' manages it"
    fi
    return 0
  fi
  if ! command -v brew >/dev/null 2>&1; then
    _warn "Homebrew not found — install ghostty with: brew install --cask ghostty"
    return 0
  fi

  _info "installing ghostty (brew cask)…"
  if brew install --cask ghostty; then
    _ok "ghostty installed"
    return 0
  fi
  _error "brew install --cask ghostty failed"
  return 1
}

_ghostty_install_linux() {
  local interactive="${1:-1}" family
  if _ghostty_installed; then
    _skip "ghostty already installed: $(command -v ghostty)"
    return 0
  fi

  family="$(_ghostty_linux_family)"
  case "${family}" in
    ubuntu) ;;
    debian)
      _warn "Debian carries no ghostty package and the community PPA is Ubuntu-only"
      _warn "install the .deb from https://github.com/mkasberg/ghostty-ubuntu/releases"
      return 0
      ;;
    *)
      _warn "unsupported Linux distribution — install ghostty by hand: ${GHOSTTY_INSTALL_DOCS}"
      return 0
      ;;
  esac

  if ! _ghostty_sudo_ok "${interactive}"; then
    return 0
  fi

  if apt-cache policy ghostty 2>/dev/null | grep -qE 'Candidate: [0-9]'; then
    _info "installing ghostty (apt)…"
    if _ghostty_sudo "${interactive}" apt-get install -y ghostty; then
      _ok "ghostty installed"
    else
      _error "apt-get install ghostty failed"
      return 1
    fi
    return 0
  fi

  if ! command -v add-apt-repository >/dev/null 2>&1; then
    _warn "add-apt-repository not found (install software-properties-common) — install ghostty by hand"
    return 0
  fi

  _info "adding the ghostty PPA (no ghostty package in the archive yet)…"
  if ! _ghostty_sudo "${interactive}" add-apt-repository -y ppa:mkasberg/ghostty-ubuntu >/dev/null; then
    _warn "could not add ppa:mkasberg/ghostty-ubuntu — install ghostty by hand"
    return 0
  fi
  _ghostty_sudo "${interactive}" apt-get update -qq || true
  if _ghostty_sudo "${interactive}" apt-get install -y ghostty; then
    _ok "ghostty installed"
    return 0
  fi

  # Never leave behind the source whose install just failed: apt would keep
  # failing on it long after this run.
  _warn "apt-get install ghostty failed — removing the PPA again"
  _ghostty_sudo "${interactive}" add-apt-repository -y --remove ppa:mkasberg/ghostty-ubuntu >/dev/null 2>&1 || true
  _ghostty_sudo "${interactive}" apt-get update -qq || true
  return 0
}

# _ghostty_sudo <interactive> <command…> — run a privileged command in the mode
# the caller asked for. The probe alone is not enough: authorization can expire
# between the probe and the command, and `sudo` would then wait for a password
# an unattended update has nobody to type.
_ghostty_sudo() {
  local interactive="${1:-1}"
  shift
  if [[ "${interactive}" -eq 1 ]]; then
    sudo "$@"
  else
    sudo -n "$@"
  fi
}

# _ghostty_sudo_ok <interactive> — 0 when a privileged step may run.
_ghostty_sudo_ok() {
  local interactive="${1:-1}"
  if [[ "${interactive}" -eq 1 ]]; then
    sudo true 2>/dev/null && return 0
    _warn "sudo unavailable — install ghostty by hand: ${GHOSTTY_INSTALL_DOCS}"
    return 1
  fi
  sudo -n true 2>/dev/null && return 0
  _warn "needs sudo without a prompt — skipping the ghostty install (run 'devbot install' to be asked)"
  return 1
}

_ghostty_upgrade() {
  case "$(uname -s)" in
    Darwin)
      if ! _ghostty_cask_installed; then
        _ghostty_install_brew
        return $?
      fi
      _info "upgrading ghostty (brew cask)…"
      brew upgrade --cask ghostty || _warn "brew upgrade --cask ghostty failed — keeping the installed version"
      ;;
    Linux)
      if ! _ghostty_installed; then
        _ghostty_install_linux 0
        return $?
      fi
      if [[ "$(_ghostty_linux_family)" != "ubuntu" ]]; then
        _warn "this distribution has no devbot-managed upgrade path — update ghostty by hand"
        return 0
      fi
      if ! sudo -n true 2>/dev/null; then
        _skip "sudo needs a prompt — ghostty upgrade skipped (run 'devbot update' from a terminal)"
        return 0
      fi
      _info "upgrading ghostty (apt)…"
      # `-n` again: the probe above proved only that the helper was authorised
      # THEN, and an unattended run must not block on a prompt that appeared since.
      _ghostty_sudo 0 apt-get install -y --only-upgrade ghostty \
        || _warn "apt-get upgrade ghostty failed — keeping the installed version"
      ;;
    *)
      _warn "unsupported OS $(uname -s) — upgrade ghostty by hand"
      ;;
  esac
}

# How to make it the default: the alternative on Linux, a launch line on macOS
# (the app has no system default-terminal switch — `ghostty +list-actions` has
# none). Only called for an installed ghostty: a command pointing at a binary
# that is not there reads as advice the module already validated.
_ghostty_default_hint() {
  case "$(uname -s)" in
    Darwin)
      _info "To use ghostty as your terminal, start it with:"
      echo "    open -a Ghostty"
      ;;
    Linux)
      _info "If you want to make ghostty your default terminal, run:"
      echo "    sudo update-alternatives --set x-terminal-emulator $(command -v ghostty)"
      ;;
    *)
      # `update-alternatives` is a Linux tool: printing it on another OS would
      # hand the user a command that cannot work where we just installed.
      _info "ghostty is installed; set it as the default terminal in your desktop's settings"
      ;;
  esac
}

# _ghostty_main install|update
_ghostty_main() {
  local mode="${1:-install}"
  _info "ghostty"

  # Disabled must mean nothing happens: no package manager, no sudo, no hint.
  if ! _devbot_module_enabled ghostty; then
    _skip "ghostty module disabled — nothing installed"
    return 0
  fi

  if [[ "${mode}" == "update" ]]; then
    _ghostty_upgrade || return 1
  else
    _ghostty_install 1 || return 1
  fi

  if ! _ghostty_installed; then
    _warn "ghostty is not installed — nothing to make the default yet"
    return 0
  fi

  _ghostty_default_hint
  _ok "ghostty ready"
}
