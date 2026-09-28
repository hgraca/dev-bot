#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/devbot_db_prune_tests.bats
# Tests for _devbot_prune_opencode_db_detached and its wiring into the
# last-session release path:
#
#   - it fires only when the last devbot session releases (live count == 0);
#   - it runs `bin/prune.sh --db <days>` detached, with the retention from
#     DEVBOT_OPENCODE_DB_RETENTION_DAYS (default 30);
#   - the child does NOT inherit fd 200 (the registry lock) — it would otherwise
#     keep the registry flock alive after exit and stall the next registration;
#   - it is fail-open (no bin/prune.sh → nothing happens).
#
# Run from project root:
#   bats src/_shared/tests/devbot_db_prune_tests.bats
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "${TEST_DIR}/../../.." && pwd)"

  export DEV_BOT_ROOT="$(mktemp -d)"
  SESSIONS_DIR="${DEV_BOT_ROOT}/storage/run/sessions"
  LOG="${DEV_BOT_ROOT}/.agents/logs/opencode-db-prune.log"
  RAN_MARKER="${DEV_BOT_ROOT}/prune-ran"

  mkdir -p "${SESSIONS_DIR}" "${DEV_BOT_ROOT}/bin" "${DEV_BOT_ROOT}/mockbin"

  # Stub bin/prune.sh: record the args it was called with, and whether fd 200
  # was inherited (Linux /proc only — the fd check is skipped elsewhere).
  cat > "${DEV_BOT_ROOT}/bin/prune.sh" <<EOF
#!/usr/bin/env bash
{
  echo "args: \$*"
  if [[ -d /proc/self/fd ]]; then
    if [[ -e /proc/self/fd/200 ]]; then echo "fd200-inherited"; else echo "fd200-closed"; fi
    if [[ -e /proc/self/fd/210 ]]; then echo "fd210-inherited"; else echo "fd210-closed"; fi
  fi
} >> "${RAN_MARKER}"
exit 0
EOF
  chmod +x "${DEV_BOT_ROOT}/bin/prune.sh"

  # Stub bin/down.sh and docker so _devbot_session_release's teardown is a no-op.
  cat > "${DEV_BOT_ROOT}/bin/down.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${DEV_BOT_ROOT}/bin/down.sh"

  cat > "${DEV_BOT_ROOT}/mockbin/docker" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${DEV_BOT_ROOT}/mockbin/docker"
  export PATH="${DEV_BOT_ROOT}/mockbin:${PATH}"

  source "${PROJECT_ROOT}/src/_shared/functions.sh"
  unset _DEVBOT_SESSION_RELEASED _DEVBOT_REGISTRY_LOCK_HELD _DEVBOT_START_FAILED 2>/dev/null || true
}

teardown() {
  unset DEV_BOT_ROOT _DEVBOT_SESSION_RELEASED 2>/dev/null || true
  rm -rf "${DEV_BOT_ROOT}" 2>/dev/null || true
}

# Wait (bounded) for the detached child to drop its marker.
wait_for_marker() {
  local i
  for i in $(seq 1 50); do
    [[ -f "${RAN_MARKER}" ]] && return 0
    sleep 0.1
  done
  return 1
}

wait_for_done() {
  local i
  for i in $(seq 1 50); do
    grep -q 'opencode-db-prune-done' "${LOG}" 2>/dev/null && return 0
    sleep 0.1
  done
  return 1
}

# ── Detached launch ───────────────────────────────────────────────────────────

@test "writes the start marker synchronously" {
  run _devbot_prune_opencode_db_detached
  assert_success
  [ -f "${LOG}" ]
  run cat "${LOG}"
  assert_output --partial "[opencode-db-prune-start]"
  assert_output --partial "retention 30 day(s)"
}

@test "launches the prune script detached with --db and the retention" {
  _devbot_prune_opencode_db_detached
  wait_for_marker || flunk "detached prune did not run"
  run cat "${RAN_MARKER}"
  assert_output --partial "args: --db 30"
}

@test "records the done marker with the exit code" {
  _devbot_prune_opencode_db_detached
  wait_for_done || flunk "detached prune did not finish"
  run cat "${LOG}"
  assert_output --partial "[opencode-db-prune-done] rc=0"
}

@test "honours DEVBOT_OPENCODE_DB_RETENTION_DAYS" {
  export DEVBOT_OPENCODE_DB_RETENTION_DAYS=7
  _devbot_prune_opencode_db_detached
  wait_for_marker || flunk "detached prune did not run"
  run cat "${RAN_MARKER}"
  assert_output --partial "args: --db 7"
  run cat "${LOG}"
  assert_output --partial "retention 7 day(s)"
}

@test "child does not inherit the registry/session lock fds 200 and 210" {
  [[ -d /proc/self/fd ]] || skip "no /proc/self/fd on this platform"

  # Hold both locks the way _devbot_session_release does.
  exec 200<"${DEV_BOT_ROOT}"
  flock -n 200
  exec 210>"${DEV_BOT_ROOT}/session-test"
  flock -x 210

  _devbot_prune_opencode_db_detached
  wait_for_marker || flunk "detached prune did not run"
  run cat "${RAN_MARKER}"
  assert_output --partial "fd200-closed"
  assert_output --partial "fd210-closed"
  refute_output --partial "fd200-inherited"
  refute_output --partial "fd210-inherited"
}

@test "caps the prune log before appending" {
  mkdir -p "$(dirname "${LOG}")"
  head -c 1200000 /dev/zero | tr '\0' 'x' > "${LOG}"

  run _devbot_prune_opencode_db_detached
  assert_success
  [ -f "${LOG}.1" ]
}

@test "is fail-open when bin/prune.sh is absent" {
  export DEV_BOT_ROOT="$(mktemp -d)"
  run _devbot_prune_opencode_db_detached
  assert_success
  [ ! -e "${DEV_BOT_ROOT}/.agents/logs/opencode-db-prune.log" ]
}

# ── Wiring: only on the last-session release ──────────────────────────────────

@test "release fires the prune when no live session remains" {
  _devbot_session_release
  wait_for_marker || flunk "prune did not fire on last-session release"
  run cat "${RAN_MARKER}"
  assert_output --partial "args: --db 30"
}

@test "release does not fire the prune while another session is live" {
  # A second live session holding its own lock.
  ( exec 215>"${SESSIONS_DIR}/session-99999"; flock -x 215; sleep 5 ) &
  local holder=$!

  # Wait until the holder has actually taken the flock, so the release below
  # cannot race it and see the session as stale.
  local i
  for i in $(seq 1 50); do
    flock -n "${SESSIONS_DIR}/session-99999" -c true 2>/dev/null || break
    sleep 0.1
  done

  _devbot_session_release
  sleep 0.5
  [ ! -f "${RAN_MARKER}" ]

  kill "${holder}" 2>/dev/null || true
}
