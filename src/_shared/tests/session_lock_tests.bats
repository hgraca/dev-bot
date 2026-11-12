#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/session_lock_tests.bats
# Presence locks written by the harness start scripts and read by autobot.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  MODULE_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  LOCK_SH="${MODULE_DIR}/session_lock.sh"
  SANDBOX="$(mktemp -d)"
  PROJECT="${SANDBOX}/project"
  mkdir -p "${PROJECT}"
}

teardown() {
  rm -rf "${SANDBOX}"
}

@test "create writes a per-pid lock under the default devbot dir" {
  run bash "${LOCK_SH}" create "${PROJECT}" session
  assert_success
  local lock="${output}"
  assert [ -f "${lock}" ]
  run dirname "${lock}"
  assert_output "${PROJECT}/.agents/state/devbot"
}

@test "the lock body records the pid and kind" {
  lock="$(bash "${LOCK_SH}" create "${PROJECT}" session)"
  run python3 "${MODULE_DIR}/read_jsonc.py" "${lock}" pid
  assert_output --regexp '^[0-9]+$'
  run python3 "${MODULE_DIR}/read_jsonc.py" "${lock}" kind
  assert_output "session"
}

@test "records the pid the caller passes, in the payload and the filename" {
  lock="$(bash "${LOCK_SH}" create "${PROJECT}" session 4242)"
  run python3 "${MODULE_DIR}/read_jsonc.py" "${lock}" pid
  assert_output "4242"
  run basename "${lock}"
  assert_output "4242.json"
}

@test "create honours a project-specific devbot_dir" {
  printf '{"devbot_dir": ".runtime"}\n' > "${PROJECT}/.devbot.project.jsonc"
  lock="$(bash "${LOCK_SH}" create "${PROJECT}" session)"
  run dirname "${lock}"
  assert_output "${PROJECT}/.runtime/state/devbot"
}

@test "remove deletes the lock" {
  lock="$(bash "${LOCK_SH}" create "${PROJECT}" session)"
  run bash "${LOCK_SH}" remove "${lock}"
  assert_success
  refute [ -f "${lock}" ]
}

@test "remove is a no-op for a path that is not there" {
  run bash "${LOCK_SH}" remove "${SANDBOX}/absent.json"
  assert_success
}

@test "an unknown subcommand fails" {
  run bash "${LOCK_SH}" wat
  assert_failure
}
