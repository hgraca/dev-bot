#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/lock_wait_tests.bats
# Tests for _devbot_lock_wait — the cross-process flock helper.
#
# Run from project root:
#   bats src/_shared/tests/lock_wait_tests.bats
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"

  SANDBOX_DIR="$(mktemp -d)"
  export DEV_BOT_ROOT="${SANDBOX_DIR}"
  # shellcheck source=../functions.sh
  source "${PROJECT_ROOT}/src/_shared/functions.sh"
}

teardown() {
  rm -rf "${SANDBOX_DIR}" 2>/dev/null || true
}

@test "lock_wait acquires a free lock" {
  run _devbot_lock_wait "${SANDBOX_DIR}/test.lock" 0 ""
  assert_success
}

@test "lock_wait returns 1 when the lock is held and the cap is 0" {
  # Hold an exclusive lock on the same file from another process.
  ( exec 205>"${SANDBOX_DIR}/held.lock"; flock -x 205; sleep 3 ) &
  local holder=$!
  sleep 0.3

  run _devbot_lock_wait "${SANDBOX_DIR}/held.lock" 0 ""
  assert_failure

  kill "${holder}" 2>/dev/null || true
}

@test "lock_wait does not permanently silence stderr" {
  # Regression: a bare `exec 200>file 2>/dev/null` persists the redirect and
  # swallows every later _error/_fatal from the caller.
  run bash -c "
    source '${PROJECT_ROOT}/src/_shared/functions.sh'
    DEV_BOT_ROOT='${SANDBOX_DIR}'
    _devbot_lock_wait '${SANDBOX_DIR}/test.lock' 0 ''
    echo 'stderr-visible' >&2
  "
  assert_output --partial "stderr-visible"
}

@test "lock_acquire holds a lock on a descriptor the caller opened" {
  # Regression: up.sh holds the datasources lifecycle lock (its own fd) and then
  # takes the session-registry lock on 200 in the same process. Both used to
  # share one descriptor, so the second call silently released the first.
  run bash -c "
    source '${PROJECT_ROOT}/src/_shared/functions.sh'
    exec 201>'${SANDBOX_DIR}/outer.lock'
    _devbot_lock_acquire 201 0 '' || exit 10
    _devbot_lock_wait '${SANDBOX_DIR}/inner.lock' 0 '' || exit 20
    exec 202>'${SANDBOX_DIR}/outer.lock'
    _devbot_lock_acquire 202 0 '' && exit 30
    echo BOTH-HELD
    exit 7
  "
  assert_output --partial "BOTH-HELD"
  [ "$status" -eq 7 ]
}

@test "lock_wait never evaluates the lock path" {
  # A checkout or runtime dir whose name carries shell syntax must not run. The
  # path is opened directly; an eval here would execute $() while locking.
  local marker="${SANDBOX_DIR}/pwned"
  local dir="${SANDBOX_DIR}/weird\$(touch ${marker})"
  mkdir -p "${dir}"

  run bash -c "
    source '${PROJECT_ROOT}/src/_shared/functions.sh'
    exec 201>'${dir}/x.lock'
    _devbot_lock_acquire 201 0 '' || exit 1
    echo LOCKED
  "
  assert_output --partial "LOCKED"
  [ ! -e "${marker}" ]
}
