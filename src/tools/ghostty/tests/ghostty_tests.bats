#!/usr/bin/env bats
# =============================================================================
# src/tools/ghostty/tests/ghostty_tests.bats
# The ghostty module: install the terminal on Linux and macOS, and print how to
# make it the default instead of changing it.
#
# No package manager, sudo, brew or network is touched: each one is a stub that
# records what it was asked to do.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  MODULE_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  PROJECT_ROOT="$(cd "${MODULE_ROOT}/../.." && pwd)"

  export HOME="${BATS_TEST_TMPDIR}/home"
  export SANDBOX_BIN="${HOME}/bin"
  mkdir -p "${HOME}" "${SANDBOX_BIN}"

  # The gate reads the shipped dist too (a module the config does not mention
  # takes the dist default), so the sandbox root carries one.
  export DEV_BOT_ROOT="${BATS_TEST_TMPDIR}/root"
  mkdir -p "${DEV_BOT_ROOT}"
  echo '{"modules": {}}' >"${DEV_BOT_ROOT}/.devbot.global.dist.jsonc"

  export DEV_BOT_GLOBAL_CONFIG="${BATS_TEST_TMPDIR}/global.jsonc"
  echo '{"modules": {}}' >"${DEV_BOT_GLOBAL_CONFIG}"
  cd "${BATS_TEST_TMPDIR}" || return 1

  export TEST_UNAME="Linux"
  export APT_HAS_GHOSTTY=1
  export APT_INSTALL_FAILS=0
  export BREW_HAS_GHOSTTY=0
  export SUDO_N_FAILS=0
  : >"${BATS_TEST_TMPDIR}/calls"

  # uname: the module branches on it, nothing else in these tests does.
  cat >"${SANDBOX_BIN}/uname" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  -s) echo "${TEST_UNAME}" ;;
  *) echo "${TEST_UNAME}" ;;
esac
EOF

  cat >"${SANDBOX_BIN}/ghostty" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

  cat >"${SANDBOX_BIN}/sudo" <<'EOF'
#!/usr/bin/env bash
echo "sudo $*" >>"${BATS_TEST_TMPDIR}/calls"
if [[ "${1:-}" == "-n" ]]; then
  [[ "${SUDO_N_FAILS:-0}" == "1" ]] && exit 1
  shift
fi
"$@"
EOF

  cat >"${SANDBOX_BIN}/apt-cache" <<'EOF'
#!/usr/bin/env bash
echo "apt-cache $*" >>"${BATS_TEST_TMPDIR}/calls"
if [[ "${APT_HAS_GHOSTTY:-1}" == "1" ]]; then
  echo "  Candidate: 1.3.1"
else
  echo "  Candidate: (none)"
fi
EOF

  cat >"${SANDBOX_BIN}/apt-get" <<'EOF'
#!/usr/bin/env bash
echo "apt-get $*" >>"${BATS_TEST_TMPDIR}/calls"
if [[ "${APT_INSTALL_FAILS:-0}" == "1" && "$1" == "install" ]]; then exit 100; fi
exit 0
EOF

  cat >"${SANDBOX_BIN}/add-apt-repository" <<'EOF'
#!/usr/bin/env bash
echo "add-apt-repository $*" >>"${BATS_TEST_TMPDIR}/calls"
exit 0
EOF

  cat >"${SANDBOX_BIN}/brew" <<'EOF'
#!/usr/bin/env bash
echo "brew $*" >>"${BATS_TEST_TMPDIR}/calls"
case "$1" in
  list) exit "$(( BREW_HAS_GHOSTTY == 1 ? 0 : 1 ))" ;;
esac
exit 0
EOF

  chmod +x "${SANDBOX_BIN}"/*

  # A hermetic PATH: only the tools the module and this file need, symlinked from
  # the host. Without it the host's own /usr/bin/ghostty answers `command -v`,
  # and every "not installed" case would silently take the installed path.
  local system_bin="${BATS_TEST_TMPDIR}/system-bin"
  mkdir -p "${system_bin}"
  local tool
  for tool in bash sh awk sed grep cat cmp mktemp chmod mv rm mkdir dirname env id head tail tr cut sort jq python3; do
    [[ -n "$(command -v "${tool}" 2>/dev/null)" ]] && ln -sf "$(command -v "${tool}")" "${system_bin}/${tool}"
  done
  export PATH="${SANDBOX_BIN}:${system_bin}"

  source "${MODULE_ROOT}/functions.sh"
}

# `command -v ghostty` must answer "missing".
_without_ghostty() {
  mv "${SANDBOX_BIN}/ghostty" "${BATS_TEST_TMPDIR}/ghostty.bin"
}

# ── macOS ────────────────────────────────────────────────────────────────────

@test "macOS installs the brew cask when ghostty is missing" {
  export TEST_UNAME=Darwin
  _without_ghostty

  run _ghostty_install 1

  assert_success
  run cat "${BATS_TEST_TMPDIR}/calls"
  assert_output --partial "brew install --cask ghostty"
}

@test "macOS leaves an installed cask alone" {
  export TEST_UNAME=Darwin
  export BREW_HAS_GHOSTTY=1

  run _ghostty_install 1

  assert_success
  run cat "${BATS_TEST_TMPDIR}/calls"
  refute_output --partial "brew install"
}

@test "macOS treats a .dmg install as installed and never runs brew install" {
  # The documented first route on macOS is dragging the .dmg to Applications;
  # a cask-only probe would turn that into a failing `brew install` every run.
  export TEST_UNAME=Darwin
  export BREW_HAS_GHOSTTY=0
  _ghostty_installed() { return 0; }

  run _ghostty_install 1

  assert_success
  run cat "${BATS_TEST_TMPDIR}/calls"
  refute_output --partial "brew install"
}

@test "macOS says how to start it, not how to make it default" {
  export TEST_UNAME=Darwin

  run _ghostty_default_hint

  assert_success
  assert_output --partial "open -a Ghostty"
  refute_output --partial "update-alternatives"
}

@test "macOS update upgrades the cask" {
  export TEST_UNAME=Darwin
  export BREW_HAS_GHOSTTY=1

  run _ghostty_upgrade

  assert_success
  run cat "${BATS_TEST_TMPDIR}/calls"
  assert_output --partial "brew upgrade --cask ghostty"
}

# ── Linux: Ubuntu ───────────────────────────────────────────────────────────

@test "Ubuntu installs from apt when the distro carries ghostty" {
  _ghostty_linux_family() { echo ubuntu; }
  _without_ghostty

  run _ghostty_install 1

  assert_success
  run cat "${BATS_TEST_TMPDIR}/calls"
  assert_output --partial "apt-get install -y ghostty"
  refute_output --partial "add-apt-repository"
}

@test "Ubuntu adds the PPA when no package exists, then installs" {
  _ghostty_linux_family() { echo ubuntu; }
  export APT_HAS_GHOSTTY=0
  _without_ghostty

  run _ghostty_install 1

  assert_success
  run cat "${BATS_TEST_TMPDIR}/calls"
  assert_output --partial "add-apt-repository -y ppa:mkasberg/ghostty-ubuntu"
  assert_output --partial "apt-get install -y ghostty"
  run grep -n "add-apt-repository\|apt-get install" "${BATS_TEST_TMPDIR}/calls"
  assert_line --index 0 --partial "add-apt-repository"
}

@test "an unattended PPA install keeps every privileged command prompt-free" {
  # The probe proves authorization for an instant; each command must carry the
  # non-interactive flag itself or the update can block on a password.
  _ghostty_linux_family() { echo ubuntu; }
  export APT_HAS_GHOSTTY=0
  _without_ghostty

  run _ghostty_install_linux 0

  assert_success
  run cat "${BATS_TEST_TMPDIR}/calls"
  refute_output --regexp '^sudo (apt-get|add-apt-repository)'
  assert_output --partial "sudo -n add-apt-repository"
  assert_output --partial "sudo -n apt-get install"
}

@test "Ubuntu removes the PPA again when the install it was added for fails" {
  _ghostty_linux_family() { echo ubuntu; }
  export APT_HAS_GHOSTTY=0
  export APT_INSTALL_FAILS=1
  _without_ghostty

  run _ghostty_install 1

  assert_success
  run cat "${BATS_TEST_TMPDIR}/calls"
  assert_output --partial "add-apt-repository -y --remove ppa:mkasberg/ghostty-ubuntu"
}

@test "Linux leaves an installed ghostty alone" {
  run _ghostty_install 1

  assert_success
  assert_output --partial "ghostty already installed"
  run cat "${BATS_TEST_TMPDIR}/calls"
  refute_output --partial "apt-get install"
}

@test "Linux hint names the update-alternatives command" {
  run _ghostty_default_hint

  assert_success
  assert_output --partial "sudo update-alternatives --set x-terminal-emulator"
  assert_output --partial "${SANDBOX_BIN}/ghostty"
}

@test "an unattended update never waits for a sudo password" {
  _ghostty_linux_family() { echo ubuntu; }
  export SUDO_N_FAILS=1
  _without_ghostty

  run _ghostty_upgrade

  assert_success
  assert_output --partial "needs sudo without a prompt"
  run cat "${BATS_TEST_TMPDIR}/calls"
  refute_output --partial "apt-get"
}

@test "an unattended update upgrades an installed ghostty" {
  _ghostty_linux_family() { echo ubuntu; }

  run _ghostty_upgrade

  assert_success
  run cat "${BATS_TEST_TMPDIR}/calls"
  assert_output --partial "apt-get install -y --only-upgrade ghostty"
}

# ── Linux: other distributions ──────────────────────────────────────────────

@test "Debian is told the PPA is Ubuntu-only and gets no source added" {
  _ghostty_linux_family() { echo debian; }
  _without_ghostty

  run _ghostty_install 1

  assert_success
  assert_output --partial "PPA is Ubuntu-only"
  assert_output --partial "mkasberg/ghostty-ubuntu/releases"
  run cat "${BATS_TEST_TMPDIR}/calls"
  refute_output --partial "add-apt-repository"
  refute_output --partial "apt-get install"
}

@test "a non-apt distribution is told to install by hand, with no sudo prompt" {
  _ghostty_linux_family() { echo other; }
  _without_ghostty

  run _ghostty_install 1

  assert_success
  assert_output --partial "unsupported Linux distribution"
  run cat "${BATS_TEST_TMPDIR}/calls"
  refute_output --partial "sudo"
  refute_output --partial "apt-get"
  refute_output --partial "software-properties-common"
}

@test "os-release decides the Linux route" {
  local osr="${BATS_TEST_TMPDIR}/os-release"
  export GHOSTTY_OS_RELEASE="${osr}"

  printf 'ID=ubuntu\nVERSION_CODENAME=noble\n' >"${osr}"
  run _ghostty_linux_family
  assert_output "ubuntu"

  # A derivative follows its parent.
  printf 'ID=linuxmint\nID_LIKE="ubuntu debian"\n' >"${osr}"
  run _ghostty_linux_family
  assert_output "ubuntu"

  printf 'ID=debian\nVERSION_CODENAME=bookworm\n' >"${osr}"
  run _ghostty_linux_family
  assert_output "debian"

  # Neither names a Debian family: no route, even though apt tooling may exist.
  printf 'ID=fedora\n' >"${osr}"
  run _ghostty_linux_family
  assert_output "other"
}

@test "an unreadable os-release falls back to the package manager it can see" {
  export GHOSTTY_OS_RELEASE="${BATS_TEST_TMPDIR}/absent-os-release"

  run _ghostty_linux_family
  assert_output "ubuntu"

  # Without apt at all there is no route.
  mv "${SANDBOX_BIN}/apt-get" "${BATS_TEST_TMPDIR}/apt-get.bin"
  run _ghostty_linux_family
  assert_output "other"
  mv "${BATS_TEST_TMPDIR}/apt-get.bin" "${SANDBOX_BIN}/apt-get"
}

@test "an OS without update-alternatives gets no Linux command" {
  export TEST_UNAME=FreeBSD

  run _ghostty_default_hint

  assert_success
  refute_output --partial "update-alternatives"
  assert_output --partial "desktop's settings"
}

# ── Gate and dispatch ────────────────────────────────────────────────────────

@test "a disabled module touches no package manager and prints no hint" {
  echo '{"modules": {"ghostty": false}}' >"${DEV_BOT_GLOBAL_CONFIG}"
  _without_ghostty

  run _ghostty_main install

  assert_success
  assert_output --partial "ghostty module disabled"
  refute_output --partial "update-alternatives"
  run cat "${BATS_TEST_TMPDIR}/calls"
  refute_output --partial "apt-get"
  refute_output --partial "brew"
}

@test "an enabled install ends with the default hint" {
  run _ghostty_main install

  assert_success
  assert_output --partial "If you want to make ghostty your default terminal"
  assert_output --partial "update-alternatives"
  assert_output --partial "ghostty ready"
}

@test "a skipped install reports that there is nothing to default" {
  export SUDO_N_FAILS=1
  _ghostty_install() { _ghostty_install_linux 0; }
  _without_ghostty

  run _ghostty_main install

  assert_success
  assert_output --partial "ghostty is not installed"
  refute_output --partial "update-alternatives"
  refute_output --partial "ghostty ready"
}

@test "an unsupported OS is told to install by hand" {
  export TEST_UNAME=FreeBSD
  _without_ghostty

  run _ghostty_install 1

  assert_success
  assert_output --partial "unsupported OS FreeBSD"
  run cat "${BATS_TEST_TMPDIR}/calls"
  refute_output --partial "apt-get"
  refute_output --partial "brew install"
}
