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
  RECONCILE_MARKER="${DEV_BOT_ROOT}/reconcile-called"

  # Stub bin/down.sh — the real one runs docker compose down.
  mkdir -p "${DEV_BOT_ROOT}/bin"
  cat > "${DEV_BOT_ROOT}/bin/down.sh" <<EOF
#!/usr/bin/env bash
echo "down-called lock-held=\${_DEVBOT_REGISTRY_LOCK_HELD:-0}" >> "${DOWN_MARKER}"
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

@test "register releases the registry lock after publishing its file" {
  # register takes the registry lock to publish atomically; if it kept the lock,
  # the directory would stay locked for the whole session.
  _devbot_session_register
  run flock -n "${SESSIONS_DIR}" -c true
  assert_success
  exec 210>&- 2>/dev/null || true
}

# ── Project identity ─────────────────────────────────────────────────────────
# A session records which project it serves so a datasource sidecar's demand can
# be derived from the live set (_devbot_live_session_projects). Legacy session
# files written before this are empty and must stay harmless.

@test "register records the given project dir in its session file" {
  _devbot_session_register "${DEV_BOT_ROOT}"
  run cat "${SESSIONS_DIR}/session-$$"
  assert_output "${DEV_BOT_ROOT}"
  exec 210>&- 2>/dev/null || true
}

@test "register defaults the recorded project to the current directory" {
  _devbot_session_register
  run cat "${SESSIONS_DIR}/session-$$"
  assert_output "$(pwd)"
  exec 210>&- 2>/dev/null || true
}

@test "live_session_projects lists the project of a live session" {
  mkdir -p "${SESSIONS_DIR}"
  printf '%s\n' "/proj/alpha" >"${SESSIONS_DIR}/session-11111"
  ( exec 215<>"${SESSIONS_DIR}/session-11111"; flock -x 215; sleep 3 ) &
  local holder=$!
  sleep 0.3

  run _devbot_live_session_projects
  assert_output "/proj/alpha"

  kill "${holder}" 2>/dev/null || true
}

@test "live_session_projects deduplicates two sessions in the same project" {
  mkdir -p "${SESSIONS_DIR}"
  printf '%s\n' "/proj/shared" >"${SESSIONS_DIR}/session-11111"
  printf '%s\n' "/proj/shared" >"${SESSIONS_DIR}/session-22222"
  ( exec 215<>"${SESSIONS_DIR}/session-11111"; flock -x 215; sleep 3 ) &
  local h1=$!
  ( exec 216<>"${SESSIONS_DIR}/session-22222"; flock -x 216; sleep 3 ) &
  local h2=$!
  sleep 0.3

  run _devbot_live_session_projects
  assert_output "/proj/shared"

  kill "${h1}" "${h2}" 2>/dev/null || true
}

@test "live_session_projects ignores a legacy empty (live) session file" {
  mkdir -p "${SESSIONS_DIR}"
  : >"${SESSIONS_DIR}/session-22222"
  ( exec 215<>"${SESSIONS_DIR}/session-22222"; flock -x 215; sleep 3 ) &
  local holder=$!
  sleep 0.3

  run _devbot_live_session_projects
  assert_output ""

  kill "${holder}" 2>/dev/null || true
}

@test "live_session_projects ignores a stale file but does not prune it" {
  # A lock-free probe must not prune: a removal in the window between a
  # registering session's open and its flock would unlink the file that session
  # just opened, losing it from the registry for good. Only a lock-holding
  # caller (release, down.sh) prunes.
  mkdir -p "${SESSIONS_DIR}"
  printf '%s\n' "/proj/ghost" >"${SESSIONS_DIR}/session-33333"

  run _devbot_live_session_projects
  assert_output ""
  [ -e "${SESSIONS_DIR}/session-33333" ]
}

# ── Release: last session tears down ─────────────────────────────────────────

@test "release tears the containers down when it was the LAST session" {
  _devbot_session_register
  _devbot_session_release
  [ -f "${DOWN_MARKER}" ]
}

@test "teardown tells down.sh the registry lock is already held" {
  # The release path holds the registry lock across the teardown, so down.sh
  # must be told not to re-lock the same directory — that would deadlock.
  _devbot_session_register
  _devbot_session_release
  run cat "${DOWN_MARKER}"
  assert_output --partial "lock-held=1"
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

@test "release reconciles module services while another session is still live" {
  # A sidecar whose last consumer left must be stopped now, not at the next
  # boot — so a module's reconcile.sh runs on release, inside the registry lock.
  mkdir -p "${DEV_BOT_ROOT}/src/agentic/fakemod"
  cat >"${DEV_BOT_ROOT}/src/agentic/fakemod/reconcile.sh" <<EOF
#!/usr/bin/env bash
echo "reconciled lock-held=\${_DEVBOT_REGISTRY_LOCK_HELD:-0}" >> "${RECONCILE_MARKER}"
EOF
  chmod +x "${DEV_BOT_ROOT}/src/agentic/fakemod/reconcile.sh"

  _devbot_session_register
  mkdir -p "${SESSIONS_DIR}"
  ( exec 215>"${SESSIONS_DIR}/session-99999"; flock -x 215; sleep 3 ) &
  local holder=$!
  sleep 0.3

  _devbot_session_release

  run cat "${RECONCILE_MARKER}"
  assert_success
  assert_output --partial "lock-held=1"

  kill "${holder}" 2>/dev/null || true
}

@test "release skips the reconcile when it was the last session" {
  # With no session left the teardown removes everything, sidecars included, so
  # reconciling first would be wasted work.
  mkdir -p "${DEV_BOT_ROOT}/src/agentic/fakemod"
  cat >"${DEV_BOT_ROOT}/src/agentic/fakemod/reconcile.sh" <<EOF
#!/usr/bin/env bash
echo reconciled >> "${RECONCILE_MARKER}"
EOF
  chmod +x "${DEV_BOT_ROOT}/src/agentic/fakemod/reconcile.sh"

  _devbot_session_register
  _devbot_session_release

  [ -f "${DOWN_MARKER}" ]
  [ ! -f "${RECONCILE_MARKER}" ]
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

# ── Release: no DB prune on the exit path ────────────────────────────────────
# The opencode DB prune (bin/prune.sh --db) once fired detached from the
# last-session release. It VACUUMs the whole database file, which cost minutes
# of CPU per exit to reclaim a few MB, so it is manual-only now. This guard
# fails if the prune is put back on the exit path.

@test "release does not fire the opencode DB prune" {
  PRUNE_MARKER="${DEV_BOT_ROOT}/prune-called"
  cat > "${DEV_BOT_ROOT}/bin/prune.sh" <<EOF
#!/usr/bin/env bash
echo "prune-called args: \$*" >> "${PRUNE_MARKER}"
exit 0
EOF
  chmod +x "${DEV_BOT_ROOT}/bin/prune.sh"

  _devbot_session_register
  _devbot_session_release
  sleep 0.5

  # The release path did run to completion (teardown happened)…
  [ -f "${DOWN_MARKER}" ]
  # …but never shelled out to the prune.
  [ ! -f "${PRUNE_MARKER}" ]
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

# ── No leftover lock file ────────────────────────────────────────────────────
# The registry lock is the sessions DIRECTORY itself (flock on a dir fd), not
# a lock file — so the sessions dir contains only session files, and release
# leaves nothing behind.

@test "release leaves no lock file behind — sessions dir holds no files after" {
  _devbot_session_register
  _devbot_session_release
  run bash -c "find '${SESSIONS_DIR}' -maxdepth 1 -type f | wc -l | tr -d ' '"
  assert_output "0"
}
