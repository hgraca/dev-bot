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
  OWNERS_DIR="${DEV_BOT_ROOT}/storage/run/owners"
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
  { exec 210>&-; } 2>/dev/null || true
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
  { exec 210>&-; } 2>/dev/null || true
}

@test "register releases the registry lock after publishing its file" {
  # register takes the registry lock to publish atomically; if it kept the lock,
  # the directory would stay locked for the whole session.
  _devbot_session_register
  run flock -n "${SESSIONS_DIR}" -c true
  assert_success
  { exec 210>&-; } 2>/dev/null || true
}

# ── Project identity ─────────────────────────────────────────────────────────
# A session records which project it serves so a datasource sidecar's demand can
# be derived from the live set (_devbot_live_session_projects). Legacy session
# files written before this are empty and must stay harmless.

@test "register records the given project dir in its session file" {
  _devbot_session_register "${DEV_BOT_ROOT}"
  run cat "${SESSIONS_DIR}/session-$$"
  assert_output "${DEV_BOT_ROOT}"
  { exec 210>&-; } 2>/dev/null || true
}

@test "register defaults the recorded project to the current directory" {
  _devbot_session_register
  run cat "${SESSIONS_DIR}/session-$$"
  assert_output "$(pwd)"
  { exec 210>&-; } 2>/dev/null || true
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

# ── Container ownership ──────────────────────────────────────────────────────
# A caller that is not a session (herdr) claims the stack; while its claim is
# live a session exit must leave the containers alone, and only the owner's
# `devbot down --owner` ends them. A claim is live while the process it names
# exists AND still carries the start time recorded with it — a recycled pid
# must not pin the stack.

@test "owner claim records the name, the pid and the process start" {
  sleep 5 &
  local holder=$!
  _devbot_owner_claim herdr "${holder}"
  [ -f "${OWNERS_DIR}/owner-herdr-${holder}" ]
  run cat "${OWNERS_DIR}/owner-herdr-${holder}"
  assert_line --index 0 "herdr"
  assert_line --index 1 "${holder}"
  assert_line --index 2 --regexp '.+'

  kill "${holder}" 2>/dev/null || true
}

@test "owner claim refuses a name that cannot be a claim file" {
  run _devbot_owner_claim '../evil' "$$"
  assert_failure
  [ ! -e "${OWNERS_DIR}" ]
}

@test "owner claim refuses a pid that is not a number" {
  run _devbot_owner_claim herdr abc
  assert_failure
}

@test "owner claim refuses pid 0 — a process group is not a process" {
  # kill -0 0 always answers, so such a claim would look live forever.
  run _devbot_owner_claim herdr 0
  assert_failure
  [ ! -e "${OWNERS_DIR}/owner-herdr-0" ]
}

@test "owner claim refuses a pid with a leading zero" {
  # 007 is not a pid the kernel knows, and it names a different claim file
  # than 7 — a release could never match it.
  sleep 5 &
  local holder=$!
  run _devbot_owner_claim herdr "0${holder}"

  assert_failure
  [ ! -e "${OWNERS_DIR}/owner-herdr-0${holder}" ]

  kill "${holder}" 2>/dev/null || true
}

@test "owner claim refuses a pid whose start time cannot be read" {
  # Without the start time the claim could only use pid liveness — the
  # recycling hole the recorded start exists to close.
  sleep 5 &
  local holder=$!
  # Bats runs each test in its own subshell, so the override cannot leak.
  _devbot_process_start() { :; }

  run _devbot_owner_claim herdr "${holder}"

  assert_failure
  assert_output --partial "cannot read the start time"
  [ ! -e "${OWNERS_DIR}/owner-herdr-${holder}" ]

  kill "${holder}" 2>/dev/null || true
}

@test "owner claim refuses to publish when the registry lock cannot be taken" {
  # Publishing outside the lock is the race the lock closes: a teardown could
  # have finished its no-owner probe and remove a stack just claimed.
  sleep 5 &
  local holder=$!
  _devbot_owner_lock_take() { return 1; }

  run _devbot_owner_claim herdr "${holder}"

  assert_failure
  [ ! -e "${OWNERS_DIR}/owner-herdr-${holder}" ]

  kill "${holder}" 2>/dev/null || true
}

@test "a claim with no start line is stale" {
  sleep 5 &
  local holder=$!
  mkdir -p "${OWNERS_DIR}"
  printf 'herdr\n%s\n' "${holder}" >"${OWNERS_DIR}/owner-herdr-${holder}"

  run _devbot_live_owner_count --prune
  assert_output "0"
  [ ! -e "${OWNERS_DIR}/owner-herdr-${holder}" ]

  kill "${holder}" 2>/dev/null || true
}

@test "owner claim refuses a pid that is not a live process" {
  # Such a claim would be pruned by the next gate, so reporting it as
  # registered would tell the owner it holds a stack it does not.
  run _devbot_owner_claim herdr 999999
  assert_failure
  [ ! -e "${OWNERS_DIR}/owner-herdr-999999" ]
}

@test "live_owner_names lists a live claim and prunes a dead-pid claim" {
  sleep 5 &
  local holder=$!
  _devbot_owner_claim herdr "${holder}"
  mkdir -p "${OWNERS_DIR}"
  printf 'ghost\n999999\n' >"${OWNERS_DIR}/owner-ghost-999999"

  run _devbot_live_owner_names --prune
  assert_output "herdr"
  [ ! -e "${OWNERS_DIR}/owner-ghost-999999" ]

  kill "${holder}" 2>/dev/null || true
}

@test "live_owner_names does not prune without --prune" {
  # Only a caller holding the registry lock may prune; a lock-free probe must
  # not remove a claim it merely judged stale.
  mkdir -p "${OWNERS_DIR}"
  printf 'ghost\n999999\n' >"${OWNERS_DIR}/owner-ghost-999999"

  run _devbot_live_owner_names
  assert_output ""
  [ -e "${OWNERS_DIR}/owner-ghost-999999" ]
}

@test "process start is independent of the caller's time zone" {
  # lstart renders in local time: a claim written under one TZ and read under
  # another would differ for the same process and read as a stale owner.
  sleep 5 &
  local holder=$!
  local plus14 minus9
  plus14="$(TZ=Pacific/Kiritimati _devbot_process_start "${holder}")"
  minus9="$(TZ=America/Anchorage _devbot_process_start "${holder}")"
  [ -n "${plus14}" ]
  [ "${plus14}" = "${minus9}" ]

  kill "${holder}" 2>/dev/null || true
}

@test "process start is the kernel tick counter where /proc exists" {
  # Whole-second lstart could miss a pid recycled within the same second.
  [ -r "/proc/$$/stat" ] || skip "no /proc on this host"
  sleep 5 &
  local holder=$!
  run _devbot_process_start "${holder}"
  assert_output --regexp '^[0-9]+$'

  kill "${holder}" 2>/dev/null || true
}

@test "a claim whose pid now belongs to another process is stale" {
  # The kernel recycles pids; the recorded start time is what tells the owner
  # from the stranger that inherited its number.
  sleep 5 &
  local holder=$!
  mkdir -p "${OWNERS_DIR}"
  printf 'herdr\n%s\nThu Jan  1 00:00:00 1970\n' "${holder}" >"${OWNERS_DIR}/owner-herdr-${holder}"

  run _devbot_live_owner_count --prune
  assert_output "0"
  [ ! -e "${OWNERS_DIR}/owner-herdr-${holder}" ]

  kill "${holder}" 2>/dev/null || true
}

@test "a claim file with no name line is stale, not a live owner" {
  # Names and count must agree: a nameless file would otherwise keep the stack
  # while `down` had no owner to name.
  sleep 5 &
  local holder=$!
  mkdir -p "${OWNERS_DIR}"
  : >"${OWNERS_DIR}/owner-nameless-${holder}"
  printf '%s\n' "${holder}" >>"${OWNERS_DIR}/owner-nameless-${holder}"

  run _devbot_live_owner_count --prune
  assert_output "0"
  run _devbot_live_owner_names
  assert_output ""
  [ ! -e "${OWNERS_DIR}/owner-nameless-${holder}" ]

  kill "${holder}" 2>/dev/null || true
}

@test "owner_release drops exactly one claim" {
  mkdir -p "${OWNERS_DIR}"
  printf 'herdr\n1111\n\n' >"${OWNERS_DIR}/owner-herdr-1111"
  printf 'herdr\n2222\n\n' >"${OWNERS_DIR}/owner-herdr-2222"

  _devbot_owner_release herdr 1111

  [ ! -e "${OWNERS_DIR}/owner-herdr-1111" ]
  [ -e "${OWNERS_DIR}/owner-herdr-2222" ]
}

@test "owner_release warns when no claim matches the name and pid" {
  # A pid mismatch would otherwise look like a successful release, and the gate
  # would then report the very owner the caller just asked to release.
  mkdir -p "${OWNERS_DIR}"
  printf 'herdr\n1111\n\n' >"${OWNERS_DIR}/owner-herdr-1111"

  run _devbot_owner_release herdr 2222
  assert_success
  assert_output --partial "no container owner claim 'herdr' for pid 2222"
  [ -e "${OWNERS_DIR}/owner-herdr-1111" ]
}

@test "release keeps the containers while a registered owner is live" {
  sleep 5 &
  local holder=$!
  _devbot_owner_claim herdr "${holder}"

  run bash -c "
    export DEV_BOT_ROOT='${DEV_BOT_ROOT}'
    source '${PROJECT_ROOT}/src/_shared/functions.sh'
    _devbot_session_register
    _devbot_session_release
  "

  assert_success
  assert_output --partial "Container owner 'herdr' holds the stack — nothing changed"
  [ ! -f "${DOWN_MARKER}" ]

  kill "${holder}" 2>/dev/null || true
}

@test "release does not reconcile module services while an owner keeps the stack" {
  # Reconciling would converge the stack to a demand of zero while the owner
  # still wants it up.
  mkdir -p "${DEV_BOT_ROOT}/src/agentic/fakemod"
  cat >"${DEV_BOT_ROOT}/src/agentic/fakemod/reconcile.sh" <<EOF
#!/usr/bin/env bash
echo reconciled >> "${RECONCILE_MARKER}"
EOF
  chmod +x "${DEV_BOT_ROOT}/src/agentic/fakemod/reconcile.sh"

  sleep 5 &
  local holder=$!
  _devbot_owner_claim herdr "${holder}"

  run bash -c "
    export DEV_BOT_ROOT='${DEV_BOT_ROOT}'
    source '${PROJECT_ROOT}/src/_shared/functions.sh'
    _devbot_session_register
    _devbot_session_release
  "

  assert_success
  [ ! -f "${RECONCILE_MARKER}" ]
  [ ! -f "${DOWN_MARKER}" ]

  kill "${holder}" 2>/dev/null || true
}

@test "release does not reconcile even while ANOTHER session is still live" {
  # The session-driven reconcile derives sidecar demand from live sessions, so
  # with an owner holding the stack it would stop a sidecar the owner's panes
  # are using — the owner decides the stack's shape, not a session count.
  mkdir -p "${DEV_BOT_ROOT}/src/agentic/fakemod"
  cat >"${DEV_BOT_ROOT}/src/agentic/fakemod/reconcile.sh" <<EOF
#!/usr/bin/env bash
echo reconciled >> "${RECONCILE_MARKER}"
EOF
  chmod +x "${DEV_BOT_ROOT}/src/agentic/fakemod/reconcile.sh"

  sleep 5 &
  local holder=$!
  _devbot_owner_claim herdr "${holder}"
  mkdir -p "${SESSIONS_DIR}"
  ( exec 215>"${SESSIONS_DIR}/session-99999"; flock -x 215; sleep 3 ) &
  local session=$!
  sleep 0.3

  run bash -c "
    export DEV_BOT_ROOT='${DEV_BOT_ROOT}'
    source '${PROJECT_ROOT}/src/_shared/functions.sh'
    _devbot_session_register
    _devbot_session_release
  "

  assert_success
  assert_output --partial "holds the stack — nothing changed"
  [ ! -f "${RECONCILE_MARKER}" ]

  kill "${session}" "${holder}" 2>/dev/null || true
}

@test "release tears down when the only claim's pid is gone" {
  # A crashed owner must not wedge the stack: the stale claim is pruned and the
  # last session out still removes the containers.
  mkdir -p "${OWNERS_DIR}"
  printf 'herdr\n999999\n\n' >"${OWNERS_DIR}/owner-herdr-999999"

  _devbot_session_register
  _devbot_session_release

  [ -f "${DOWN_MARKER}" ]
  [ ! -e "${OWNERS_DIR}/owner-herdr-999999" ]
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

# ── stderr must survive the registry ─────────────────────────────────────────
# An `exec N>&-` close with a trailing `2>/dev/null` applies BOTH redirections
# to the current shell when
# `exec` has no command, so that redirect — meant to silence a
# failed fd close — permanently sent the whole process's stderr to /dev/null.
# Everything after registration (all of bin/up.sh, with compose's own errors)
# then failed invisibly: the reported symptom was `devbot up` tearing every
# container down and printing nothing about why. The close is now grouped so
# its redirection cannot outlive it.

@test "register leaves stderr usable — a later error is still visible" {
  run bash -c "
    export DEV_BOT_ROOT='${DEV_BOT_ROOT}'
    source '${PROJECT_ROOT}/src/_shared/functions.sh'
    _devbot_session_register
    echo 'ERROR: still visible' >&2
  "

  assert_success
  assert_output --partial "ERROR: still visible"
}

@test "release leaves stderr usable — teardown output is not swallowed" {
  run bash -c "
    export DEV_BOT_ROOT='${DEV_BOT_ROOT}'
    source '${PROJECT_ROOT}/src/_shared/functions.sh'
    _devbot_session_register
    _devbot_session_release
    echo 'ERROR: still visible' >&2
  "

  assert_success
  assert_output --partial "ERROR: still visible"
}

@test "no script opens or closes an fd with a shell-wide stderr redirect" {
  # Any `exec N>file 2>/dev/null` / `exec N>&- 2>/dev/null` applies BOTH
  # redirections to the current shell when `exec` has no command — permanently
  # silencing the process's stderr. Group it: `{ exec …; } 2>/dev/null`.
  # Anchored at the start of the statement: a subshell such as
  # `(exec 3<>"/dev/tcp/…") 2>/dev/null` is already scoped and legitimate.
  run grep -rnE '^[[:space:]]*exec [0-9]+[<>][^;]*2>[[:space:]]*/dev/null' "${PROJECT_ROOT}/bin" "${PROJECT_ROOT}/src" \
    --exclude-dir=tests
  assert_failure
  [ -z "${output}" ]
}
