#!/usr/bin/env bats
# =============================================================================
# bin/tests/up_failure_tests.bats
# `devbot up` runs under `set -euo pipefail`. Without an ERR trap an unguarded
# failure aborts the script with no line saying what broke — and the caller
# (`devbot` start) then tears the containers down, so the user sees everything
# disappear and nothing about why. These tests pin the failure reporting: the
# step in progress, the exit code and the failing command.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SANDBOX="$(mktemp -d)"

  mkdir -p "${SANDBOX}/bin" "${SANDBOX}/src/_shared"

  # The callable half of up.sh — everything but the `main "$@"` tail — so the
  # helpers can be driven without booting anything.
  sed '/^main "\$@"/d' "${PROJECT_ROOT}/bin/up.sh" > "${SANDBOX}/bin/up.sh.src"

  # Minimal shared library: the output primitives _up_failed uses.
  cat > "${SANDBOX}/src/_shared/functions.sh" <<'STUB'
#!/usr/bin/env bash
_header_1() { true; }
_header_2() { true; }
_header_3() { true; }
_info() { true; }
_ok() { true; }
_skip() { true; }
_log() { true; }
_warn() { echo "WARN: $*"; }
_error() { echo "ERROR: $*" >&2; }
_fatal() { echo "FATAL: $*" >&2; }
_fmt_duration() { echo "0s"; }
TEXT_BOLD=''
TEXT_BLUE=''
TEXT_CLEAR=''
TEXT_DIM=''
TEXT_GREEN=''
TEXT_ORANGE=''
TEXT_RED=''
TEXT_YELLOW=''
_devbot_codebase_memory_root() { echo "${HOME:-/tmp}"; }
_devbot_get_disabled_modules() { echo "[]"; }
STUB
}

teardown() {
  rm -rf "${SANDBOX}" 2>/dev/null || true
}

@test "a failure names the step in progress, the exit code and the command" {
  run bash -c "
    source '${SANDBOX}/bin/up.sh.src'
    _up_install_trap
    _UP_STEP='docker services'
    false
  "

  assert_failure
  assert_output --partial "devbot up failed during 'docker services'"
  assert_output --partial "exit 1"
  assert_output --partial "failing command: false"
}

@test "the reported step follows the phase that failed" {
  run bash -c "
    source '${SANDBOX}/bin/up.sh.src'
    _up_install_trap
    _UP_STEP='module up scripts'
    false
  "

  assert_failure
  assert_output --partial "devbot up failed during 'module up scripts'"
  refute_output --partial "during 'docker services'"
}

@test "a run with no failure reports nothing" {
  run bash -c "
    source '${SANDBOX}/bin/up.sh.src'
    _up_install_trap
    _UP_STEP='docker services'
    true
  "

  assert_success
  refute_output --partial "devbot up failed"
}

@test "the trap is installed only when up.sh is executed, never when sourced" {
  # bin/tests (and any other sourcer) must not inherit an ERR trap.
  run bash -c "source '${SANDBOX}/bin/up.sh.src'; trap -p ERR"
  assert_success
  [ -z "${output}" ]

  run grep -n '_up_install_trap$' "${PROJECT_ROOT}/bin/up.sh"
  assert_success
}

@test "every main phase sets the step it is about to run, in order" {
  local labels
  labels="$(grep -o '^  _UP_STEP="[^"]*"' "${PROJECT_ROOT}/bin/up.sh" \
    | sed 's/.*="//; s/"$//' | tr '\n' ' ')"

  [ "${labels}" = "environment codebase-memory root codebase-memory scope bind-mount sources docker services external module config module up scripts " ]
}
