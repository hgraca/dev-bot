#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/devbot_sessions_tests.bats
# Tests for the devbot session registry (install-level docker lifecycle):
#
#   _devbot_session_register  — record this session before up.sh
#   _devbot_session_release   — release + tear down if it was the LAST session
#   _devbot_session_teardown  — docker down (skipped with no daemon)
#
# Containers are install-level (one compose project `devbot`, shared by every
# session in every project), so the registry is install-level
# (storage/run/sessions/). Liveness uses flock, not pidfiles: each session
# holds an exclusive flock on its own file for its lifetime; the kernel
# releases it on ANY exit (including SIGKILL). A file whose flock is
# acquirable is stale and pruned. When no live session remains, the last
# exiting session tears the containers down.
#
# Run from project root:
#   bats src/_shared/tests/devbot_sessions_tests.bats
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"

  export DEV_BOT_ROOT="$(mktemp -d)"
  SESSIONS_DIR="${DEV_BOT_ROOT}/storage/run/sessions"
  DOWN_MARKER="${DEV_BOT_ROOT}/down-called"

  # Stub bin/down.sh — the real one runs docker compose down.
  mkdir -p "${DEV_BOT_ROOT}/bin"
  cat > "${DEV_BOT_ROOT}/bin/down.sh" <<EOF
#!/usr/bin/env bash
echo "down-called" >> "${DOWN_MARKER}"
exit 0
EOF
  chmod +x "${DEV_BOT_ROOT}/bin/down.sh"

  # Mock docker: \`docker info\` succeeds (a daemon is present).
  mkdir -p "${DEV_BOT_ROOT}/mockbin"
  cat > "${DEV_BOT_ROOT}/mockbin/docker" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "info" ]]; then exit 0; fi
exit 0
EOF
  chmod +x "${DEV_BOT_ROOT}/mockbin/docker"
  export PATH="${DEV_BOT_ROOT}/mockbin:${PATH}"

  source "${PROJECT_ROOT}/src/_shared/functions.sh"
  unset _DEVBOT_SESSION_RELEASED 2>/dev/null || true
}

teardown() {
  unset DEV_BOT_ROOT _DEVBOT_SESSION_RELEASED 2>/dev/null || true
  rm -rf "${DEV_BOT_ROOT}" 2>/dev/null || true
}

# ── Register ──────────────────────────────────────────────────────────────────

@test "register creates a session file under the install-level sessions dir" {
  _devbot_session_register
  local files
  files="$(find "${SESSIONS_DIR}" -maxdepth 1 -name 'session-*' | wc -l | tr -d ' ')"
  [ "${files}" -eq 1 ]
  exec 210>&- 2>/dev/null || true
}

@test "two registers create two session files (two live sessions)" {
  _devbot_session_register
  # Simulate a second live session holding its own lock (a background holder).
  mkdir -p "${SESSIONS_DIR}"
  ( exec 215>"${SESSIONS_DIR}/session-99999"; flock -x 215; sleep 3 ) &
  local holder=$!
  sleep 0.3

  local files
  files="$(find "${SESSIONS_DIR}" -maxdepth 1 -name 'session-*' | wc -l | tr -d ' ')"
  [ "${files}" -eq 2 ]

  kill "${holder}" 2>/dev/null || true
  exec 210>&- 2>/dev/null || true
}

# ── Release: last session tears down ─────────────────────────────────────────

@test "release tears the containers down when it was the LAST session" {
  _devbot_session_register
  _devbot_session_release
  [ -f "${DOWN_MARKER}" ]
}

@test "release leaves containers up when ANOTHER session is still live" {
  _devbot_session_register
  mkdir -p "${SESSIONS_DIR}"
  ( exec 215>"${SESSIONS_DIR}/session-99999"; flock -x 215; sleep 3 ) &
  local holder=$!
  sleep 0.3

  _devbot_session_release
  [ ! -f "${DOWN_MARKER}" ]

  kill "${holder}" 2>/dev/null || true
}

@test "release prunes a stale session file (holder gone) and does not count it" {
  mkdir -p "${SESSIONS_DIR}"
  # Stale file: created but no live holder.
  : > "${SESSIONS_DIR}/session-88888"

  _devbot_session_register
  _devbot_session_release
  # The stale file was pruned and we were the last → down.
  [ -f "${DOWN_MARKER}" ]
  [ ! -e "${SESSIONS_DIR}/session-88888" ]
}

@test "release is idempotent — a second call does not tear down twice" {
  _devbot_session_register
  _devbot_session_release
  _devbot_session_release
  run grep -c "down-called" "${DOWN_MARKER}"
  assert_output "1"
}

# ── Teardown: no docker daemon → skip ────────────────────────────────────────

@test "teardown skips (no down) when there is no docker daemon" {
  cat > "${DEV_BOT_ROOT}/mockbin/docker" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "info" ]]; then exit 1; fi
exit 0
EOF
  chmod +x "${DEV_BOT_ROOT}/mockbin/docker"

  _devbot_session_register
  _devbot_session_release
  [ ! -f "${DOWN_MARKER}" ]
}
