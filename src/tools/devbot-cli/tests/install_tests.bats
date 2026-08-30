#!/usr/bin/env bats
# =============================================================================
# src/tools/devbot-cli/tests/install_tests.bats
# Tests for src/tools/devbot-cli/install.sh — specifically that the post-install
# lifecycle step (bash-completion linking) runs on EVERY invocation, not just
# first install. Regression: an early `exit 0` on the "already linked" CLI
# guard used to mask the completion step on re-installs.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../../.." && pwd)"
  INSTALL_SH="${PROJECT_ROOT}/src/tools/devbot-cli/install.sh"
}

_setup_sandbox() {
  SANDBOX="$(mktemp -d)"
  FAKE_ROOT="${SANDBOX}/devbot-root"
  mkdir -p "${FAKE_ROOT}/bin" "${FAKE_ROOT}/src/tools/devbot-cli"
  : > "${FAKE_ROOT}/bin/devbot"
  : > "${FAKE_ROOT}/src/tools/devbot-cli/completion.sh"
  chmod +x "${FAKE_ROOT}/bin/devbot"
}

_run_install() {
  run env HOME="${SANDBOX}/home" DEV_BOT_ROOT="${FAKE_ROOT}" bash "${INSTALL_SH}"
}

@test "install.sh: completion link recreated on re-install when CLI already linked" {
  _setup_sandbox

  # First install — both CLI link and completion link are created.
  _run_install
  assert_success
  [ -L "${SANDBOX}/home/.local/bin/devbot" ]
  [ -L "${SANDBOX}/home/.local/share/bash-completion/completions/devbot" ]

  # Simulate a broken completion (deleted / never created on first install).
  rm -f "${SANDBOX}/home/.local/share/bash-completion/completions/devbot"

  # Re-install — the CLI link is already correct, but the completion step
  # must still run (it must NOT be masked by the already-linked guard).
  _run_install
  assert_success
  [ -L "${SANDBOX}/home/.local/share/bash-completion/completions/devbot" ]
}

@test "install.sh: completion linked when CLI link was missing (first install)" {
  _setup_sandbox

  _run_install
  assert_success

  [ -L "${SANDBOX}/home/.local/bin/devbot" ]
  [ "$(readlink "${SANDBOX}/home/.local/bin/devbot")" == "${FAKE_ROOT}/bin/devbot" ]
  [ -L "${SANDBOX}/home/.local/share/bash-completion/completions/devbot" ]
  [ "$(readlink "${SANDBOX}/home/.local/share/bash-completion/completions/devbot")" \
    == "${FAKE_ROOT}/src/tools/devbot-cli/completion.sh" ]
}
