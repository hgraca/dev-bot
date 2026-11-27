#!/usr/bin/env bats
# =============================================================================
# src/tools/herdr/tests/herdr_tests.bats
# The herdr module: install the binary, merge its config, own the shell wrapper.
#
# The wrapper is the point: devbot renders it into a marked block in ~/.bashrc
# and ~/.zshrc, replacing any foreign definition, so every install/update ships a
# function the user did not have to paste, and a session exiting inside herdr
# cannot tear the docker stack down.
#
# Everything runs against a temporary HOME; no herdr binary, network or apt is
# touched.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  MODULE_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  PROJECT_ROOT="$(cd "${MODULE_ROOT}/../.." && pwd)"

  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_CONFIG_HOME="${HOME}/.config"
  export SANDBOX_BIN="${HOME}/bin"
  mkdir -p "${HOME}" "${SANDBOX_BIN}"

  # A clean cwd: the gate reads the current directory's project config too.
  # The gate reads the shipped dist too (a module the config does not mention
  # takes the dist default), so the sandbox root carries one.
  export DEV_BOT_ROOT="${BATS_TEST_TMPDIR}/root"
  mkdir -p "${DEV_BOT_ROOT}"
  echo '{"modules": {}}' >"${DEV_BOT_ROOT}/.devbot.global.dist.jsonc"

  export DEV_BOT_GLOBAL_CONFIG="${BATS_TEST_TMPDIR}/global.jsonc"
  echo '{"modules": {}}' >"${DEV_BOT_GLOBAL_CONFIG}"
  cd "${BATS_TEST_TMPDIR}" || return 1

  # Stub herdr: records its argv, validates nothing, reports a clean config.
  cat >"${SANDBOX_BIN}/herdr" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"${BATS_TEST_TMPDIR}/herdr.calls"
case "\$1" in
  config) [[ -n "\${HERDR_CONFIG_CHECK_OUTPUT:-}" ]] && printf '%s\n' "\${HERDR_CONFIG_CHECK_OUTPUT}"; exit 0 ;;
  --version) echo "herdr 9.9.9" ;;
esac
exit 0
EOF
  chmod +x "${SANDBOX_BIN}/herdr"
  # A deterministic PATH: the host's own ~/.local/bin/herdr must not be
  # mistaken for this module's install.
  export PATH="${SANDBOX_BIN}:/usr/local/bin:/usr/bin:/bin"
  : >"${BATS_TEST_TMPDIR}/herdr.calls"

  # A curl stub that "installs" herdr from the official script: what the module
  # pipes into sh only has to drop a binary on PATH.
  cat >"${SANDBOX_BIN}/curl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"${BATS_TEST_TMPDIR}/curl.calls"
cat <<'INSTALLER'
printf '#!/usr/bin/env bash\nexit 0\n' >"\${HERDR_FAKE_BIN}/herdr"
chmod +x "\${HERDR_FAKE_BIN}/herdr"
INSTALLER
EOF
  chmod +x "${SANDBOX_BIN}/curl"
  export HERDR_FAKE_BIN="${SANDBOX_BIN}"

  source "${MODULE_ROOT}/functions.sh"
}

# `command -v herdr` must answer "missing" for the install path.
_without_herdr() {
  mv "${SANDBOX_BIN}/herdr" "${BATS_TEST_TMPDIR}/herdr.bin"
}

_with_herdr_back() {
  [[ -f "${BATS_TEST_TMPDIR}/herdr.bin" ]] && mv "${BATS_TEST_TMPDIR}/herdr.bin" "${SANDBOX_BIN}/herdr"
}

# ── Installing ───────────────────────────────────────────────────────────────

@test "install runs the official installer when herdr is missing" {
  _without_herdr

  run _herdr_install

  assert_success
  run cat "${BATS_TEST_TMPDIR}/curl.calls"
  assert_output --partial "https://herdr.dev/install.sh"
  run test -x "${SANDBOX_BIN}/herdr"
  assert_success
}

@test "install leaves an installed herdr alone" {
  run _herdr_install

  assert_success
  assert_output --partial "herdr already installed"
  [ ! -s "${BATS_TEST_TMPDIR}/curl.calls" ]
}

@test "update runs herdr's own updater when it is installed" {
  run _herdr_update_binary

  assert_success
  run cat "${BATS_TEST_TMPDIR}/herdr.calls"
  assert_output --partial "update"
}

@test "update installs when herdr is missing" {
  _without_herdr

  run _herdr_update_binary

  assert_success
  run cat "${BATS_TEST_TMPDIR}/curl.calls"
  assert_output --partial "https://herdr.dev/install.sh"
}

# ── Shell wrapper ────────────────────────────────────────────────────────────

@test "wire adds the managed block to every shell rc that exists" {
  printf 'export A=1\n' >"${HOME}/.bashrc"
  printf 'export B=2\n' >"${HOME}/.zshrc"

  run _herdr_wire_shell

  assert_success
  run cat "${HOME}/.bashrc"
  assert_output --partial "# >>> devbot:herdr >>>"
  run cat "${HOME}/.zshrc"
  assert_output --partial "# >>> devbot:herdr >>>"
}

@test "wire writes only the rc files that exist" {
  printf 'export A=1\n' >"${HOME}/.bashrc"

  run _herdr_wire_shell

  assert_success
  [ ! -e "${HOME}/.zshrc" ]
  run cat "${HOME}/.bashrc"
  assert_output --partial "# >>> devbot:herdr >>>"
}

@test "wire creates no rc file when neither exists" {
  run _herdr_wire_shell

  assert_success
  assert_output --partial "no ~/.bashrc or ~/.zshrc"
  [ ! -e "${HOME}/.bashrc" ]
  [ ! -e "${HOME}/.zshrc" ]
}

@test "wire renders the module's own function body" {
  printf 'x=1\n' >"${HOME}/.bashrc"

  _herdr_wire_shell

  run grep -cF -- '--owner herdr --owner-pid $$' "${HOME}/.bashrc"
  assert_output "2"
}

@test "wire replaces a foreign herdr function and its installer marker" {
  cat >"${HOME}/.bashrc" <<'EOF'
export A=1
# telamon:install.sh:herdr-devbot-up
herdr() {
    echo hand-rolled
}
export B=2
EOF

  _herdr_wire_shell

  run cat "${HOME}/.bashrc"
  assert_output --partial "export A=1"
  assert_output --partial "export B=2"
  assert_output --partial "# >>> devbot:herdr >>>"
  refute_output --partial "hand-rolled"
  refute_output --partial "telamon"
  [ "$(grep -c '^herdr() {' "${HOME}/.bashrc")" -eq 1 ]
}

@test "wire is byte-identical on a second run" {
  printf 'x=1\n' >"${HOME}/.bashrc"
  _herdr_wire_shell
  cp "${HOME}/.bashrc" "${BATS_TEST_TMPDIR}/first"

  _herdr_wire_shell

  cmp -s "${BATS_TEST_TMPDIR}/first" "${HOME}/.bashrc"
}

@test "wire refreshes a block from an older devbot release" {
  # A previous version's block must be replaced by the current body, not kept.
  printf 'x=1\n' >"${HOME}/.bashrc"
  _devbot_shell_block_upsert "${HOME}/.bashrc" herdr <<'EOF'
herdr() { echo stale-version; }
EOF

  _herdr_wire_shell

  run cat "${HOME}/.bashrc"
  refute_output --partial "stale-version"
  assert_output --partial "--owner herdr"
  [ "$(grep -c '^# >>> devbot:herdr >>>' "${HOME}/.bashrc")" -eq 1 ]
}

# ── Config merge ─────────────────────────────────────────────────────────────

@test "config merge adds [ui] window_title to a fresh config" {
  run _herdr_merge_config

  assert_success
  run cat "${XDG_CONFIG_HOME}/herdr/config.toml"
  assert_output --partial "[ui]"
  assert_output --partial 'window_title = "{terminal_title}"'
}

@test "config merge leaves an existing window_title alone" {
  mkdir -p "${XDG_CONFIG_HOME}/herdr"
  printf '[ui]\nwindow_title = "{pane}"\n' >"${XDG_CONFIG_HOME}/herdr/config.toml"

  run _herdr_merge_config

  assert_success
  run cat "${XDG_CONFIG_HOME}/herdr/config.toml"
  assert_output --partial 'window_title = "{pane}"'
  refute_output --partial "{terminal_title}"
}

@test "config merge puts the key inside an existing [ui] table" {
  mkdir -p "${XDG_CONFIG_HOME}/herdr"
  printf '[ui]\nfont_size = 12\n\n[keys]\nfoo = bar\n' >"${XDG_CONFIG_HOME}/herdr/config.toml"

  _herdr_merge_config

  run cat "${XDG_CONFIG_HOME}/herdr/config.toml"
  assert_output --partial 'window_title = "{terminal_title}"'
  [ "$(grep -c '^\[ui\]' "${XDG_CONFIG_HOME}/herdr/config.toml")" -eq 1 ]
  run grep -n 'window_title' "${XDG_CONFIG_HOME}/herdr/config.toml"
  assert_output --partial "2:"
}

@test "config merge reverts a config the setting would break" {
  mkdir -p "${XDG_CONFIG_HOME}/herdr"
  printf '[ui]\nfont_size = 12\n' >"${XDG_CONFIG_HOME}/herdr/config.toml"

  export HERDR_CONFIG_CHECK_OUTPUT="parse error at line 3"
  run _herdr_merge_config
  unset HERDR_CONFIG_CHECK_OUTPUT

  assert_success
  run cat "${XDG_CONFIG_HOME}/herdr/config.toml"
  refute_output --partial "window_title"
  [ ! -e "${XDG_CONFIG_HOME}/herdr/config.toml.devbot-bak" ]
}

@test "config merge ignores an unqualified window_title under another table" {
  # `[other] window_title` is a different key: treating it as the UI setting
  # would silently skip the merge the module exists to perform.
  mkdir -p "${XDG_CONFIG_HOME}/herdr"
  printf '[other]\nwindow_title = "x"\n' >"${XDG_CONFIG_HOME}/herdr/config.toml"

  run _herdr_merge_config

  assert_success
  run cat "${XDG_CONFIG_HOME}/herdr/config.toml"
  assert_output --partial "[ui]"
  assert_output --partial 'window_title = "{terminal_title}"'
}

@test "config merge accepts the dotted ui.window_title form" {
  mkdir -p "${XDG_CONFIG_HOME}/herdr"
  printf 'ui.window_title = "{pane}"\n' >"${XDG_CONFIG_HOME}/herdr/config.toml"

  run _herdr_merge_config

  assert_success
  assert_output --partial "already configured"
  run cat "${XDG_CONFIG_HOME}/herdr/config.toml"
  refute_output --partial "{terminal_title}"
}

@test "config merge reloads a running server" {
  _herdr_merge_config

  run cat "${BATS_TEST_TMPDIR}/herdr.calls"
  assert_output --partial "server reload-config"
}

# ── Gate ─────────────────────────────────────────────────────────────────────

@test "a disabled module installs nothing and touches no shell rc" {
  echo '{"modules": {"herdr": false}}' >"${DEV_BOT_GLOBAL_CONFIG}"
  printf 'x=1\n' >"${HOME}/.bashrc"
  _without_herdr

  run _herdr_main install

  assert_success
  assert_output --partial "herdr module disabled"
  [ ! -s "${BATS_TEST_TMPDIR}/curl.calls" ]
  run cat "${HOME}/.bashrc"
  refute_output --partial "devbot:herdr"

  _with_herdr_back
}

@test "an enabled module runs the whole sequence" {
  printf 'x=1\n' >"${HOME}/.bashrc"
  _without_herdr

  run _herdr_main install

  assert_success
  assert_output --partial "herdr wrapper in ~/.bashrc"
  run cat "${HOME}/.bashrc"
  assert_output --partial "# >>> devbot:herdr >>>"
  [ -f "${XDG_CONFIG_HOME}/herdr/config.toml" ]
}

# ── The wrapper's behaviour, not just its text ──────────────────────────────
# The module exists so that a herdr launch claims the docker stack and releases
# it on exit: text-matching the body asserts maintenance, not behaviour.

_wrapper_stub_devbot() {
  cat >"${SANDBOX_BIN}/devbot" <<EOF
#!/usr/bin/env bash
echo "devbot \$*" >>"${BATS_TEST_TMPDIR}/wrapper.calls"
[[ "\${DEVBOT_UP_FAILS:-0}" == "1" && "\$1" == "up" ]] && exit 1
exit 0
EOF
  chmod +x "${SANDBOX_BIN}/devbot"
  : >"${BATS_TEST_TMPDIR}/wrapper.calls"
}

@test "a launch claims the stack and releases it on exit" {
  printf 'x=1\n' >"${HOME}/.bashrc"
  _herdr_wire_shell
  _wrapper_stub_devbot

  run bash -c "source '${HOME}/.bashrc'; herdr"

  assert_success
  run cat "${BATS_TEST_TMPDIR}/wrapper.calls"
  assert_line --index 0 --regexp '^devbot up --owner herdr --owner-pid [0-9]+$'
  assert_line --index 1 --regexp '^devbot down --owner herdr --owner-pid [0-9]+$'
  # Same identity on both sides, or the release would not match the claim.
  local up_pid down_pid
  up_pid="$(sed -n 's/^devbot up --owner herdr --owner-pid //p' "${BATS_TEST_TMPDIR}/wrapper.calls")"
  down_pid="$(sed -n 's/^devbot down --owner herdr --owner-pid //p' "${BATS_TEST_TMPDIR}/wrapper.calls")"
  [ -n "${up_pid}" ]
  [ "${up_pid}" = "${down_pid}" ]
}

@test "a non-launch invocation never touches the stack" {
  printf 'x=1\n' >"${HOME}/.bashrc"
  _herdr_wire_shell
  _wrapper_stub_devbot

  run bash -c "source '${HOME}/.bashrc'; herdr completion zsh"

  assert_success
  [ ! -s "${BATS_TEST_TMPDIR}/wrapper.calls" ]
}

@test "every launch form claims the stack" {
  printf 'x=1\n' >"${HOME}/.bashrc"
  _herdr_wire_shell
  _wrapper_stub_devbot

  local args
  for args in "--session work" "--remote host" "session attach work"; do
    : >"${BATS_TEST_TMPDIR}/wrapper.calls"
    # shellcheck disable=SC2086  # the words are the argv under test
    run bash -c "source '${HOME}/.bashrc'; herdr ${args}"
    assert_success
    run grep -c '^devbot up --owner herdr' "${BATS_TEST_TMPDIR}/wrapper.calls"
    assert_output "1"
    run grep -c '^devbot down --owner herdr' "${BATS_TEST_TMPDIR}/wrapper.calls"
    assert_output "1"
  done
}

@test "every pass-through form leaves the stack alone" {
  printf 'x=1\n' >"${HOME}/.bashrc"
  _herdr_wire_shell
  _wrapper_stub_devbot

  local args
  for args in "--machine host herdr" "--version" "session list" "completion zsh"; do
    : >"${BATS_TEST_TMPDIR}/wrapper.calls"
    # shellcheck disable=SC2086  # the words are the argv under test
    run bash -c "source '${HOME}/.bashrc'; herdr ${args}"
    assert_success
    [ ! -s "${BATS_TEST_TMPDIR}/wrapper.calls" ]
  done
}

@test "a failed up starts herdr anyway and never releases" {
  printf 'x=1\n' >"${HOME}/.bashrc"
  _herdr_wire_shell
  _wrapper_stub_devbot
  export DEVBOT_UP_FAILS=1

  run bash -c "source '${HOME}/.bashrc'; herdr"

  assert_success
  assert_output --partial "devbot up failed — starting anyway"
  run cat "${BATS_TEST_TMPDIR}/wrapper.calls"
  refute_output --partial "devbot down"
}

# ── Guards around the user's shell rc ───────────────────────────────────────

@test "a missing function snippet leaves the rc untouched and warns" {
  printf 'x=1\n' >"${HOME}/.bashrc"
  MODULE_DIR="${BATS_TEST_TMPDIR}/empty-module"
  mkdir -p "${MODULE_DIR}"

  run _herdr_wire_shell

  assert_failure
  assert_output --partial "snippet is missing or invalid"
  run cat "${HOME}/.bashrc"
  assert_output "x=1"
}

@test "a managed block missing its end marker leaves the rc byte-identical" {
  # The strip must not land without its render: a malformed block would
  # otherwise cost the user the function entirely.
  printf 'x=1\n# >>> devbot:herdr >>>\nherdr() { echo old; }\ny=2\n' >"${HOME}/.bashrc"
  cp "${HOME}/.bashrc" "${BATS_TEST_TMPDIR}/first"

  run _herdr_wire_shell

  assert_success
  assert_output --partial "could not safely update"
  cmp -s "${BATS_TEST_TMPDIR}/first" "${HOME}/.bashrc"
}

@test "an unreadable shell rc is left alone" {
  printf 'x=1\n' >"${HOME}/.bashrc"
  chmod 000 "${HOME}/.bashrc"

  run _herdr_wire_shell

  assert_success
  assert_output --partial "could not read"
  chmod 644 "${HOME}/.bashrc"
  run cat "${HOME}/.bashrc"
  assert_output "x=1"
}

@test "a config that cannot be written is left at its previous content" {
  mkdir -p "${XDG_CONFIG_HOME}/herdr"
  printf '[ui]\nfont_size = 12\n' >"${XDG_CONFIG_HOME}/herdr/config.toml"
  chmod 444 "${XDG_CONFIG_HOME}/herdr/config.toml"

  run _herdr_merge_config

  assert_success
  assert_output --partial "could not write"
  chmod 644 "${XDG_CONFIG_HOME}/herdr/config.toml"
  run cat "${XDG_CONFIG_HOME}/herdr/config.toml"
  assert_output --partial "font_size = 12"
  refute_output --partial "window_title"
  [ ! -e "${XDG_CONFIG_HOME}/herdr/config.toml.devbot-bak" ]
}

@test "an unterminated foreign definition leaves the rc untouched and warns" {
  printf 'x=1\nherdr() {\n  echo hi\ny=2\n' >"${HOME}/.bashrc"
  cp "${HOME}/.bashrc" "${BATS_TEST_TMPDIR}/first"

  run _herdr_wire_shell

  assert_success
  assert_output --partial "could not safely update"
  cmp -s "${BATS_TEST_TMPDIR}/first" "${HOME}/.bashrc"
}

# ── Config merge against a config that is already broken ────────────────────

@test "a config that already fails to parse is left alone and named" {
  mkdir -p "${XDG_CONFIG_HOME}/herdr"
  printf 'font_size = = 12\n' >"${XDG_CONFIG_HOME}/herdr/config.toml"
  cp "${XDG_CONFIG_HOME}/herdr/config.toml" "${BATS_TEST_TMPDIR}/first"
  export HERDR_CONFIG_CHECK_OUTPUT="config parse error: TOML parse error at line 1, column 12"

  run _herdr_merge_config

  assert_success
  assert_output --partial "does not parse already"
  assert_output --partial "TOML parse error at line 1"
  cmp -s "${BATS_TEST_TMPDIR}/first" "${XDG_CONFIG_HOME}/herdr/config.toml"
  unset HERDR_CONFIG_CHECK_OUTPUT
}
