#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/gui_launch_tests.bats
# Tests for the `devbot --gui` launch helpers in functions.sh:
#
#   _devbot_gui_spec    — harness → desktop app bundle id + folder deep link
#   _devbot_launch_gui  — open the app, then hold until INT/TERM
#
# The hold is what keeps the devbot session (and its docker services) alive
# after `open` returns, so it is tested with a real background process and a
# real signal. `open` is a stub — no app is launched.
#
# Run from project root:
#   bats src/_shared/tests/gui_launch_tests.bats
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"

  FAKE_BIN="$(mktemp -d)"
  OPEN_LOG="${FAKE_BIN}/open.log"
  # Stub `open`: record the DEV_BOT_GUI it was given (written first — the argv
  # log is what the tests wait on) and argv, exit with OPEN_RC (default 0).
  cat > "${FAKE_BIN}/open" <<EOF
#!/usr/bin/env bash
printf '%s' "\${DEV_BOT_GUI-unset}" > "${OPEN_LOG}.gui"
printf '%s\n' "\$@" > "${OPEN_LOG}"
exit "\${OPEN_RC:-0}"
EOF
  chmod +x "${FAKE_BIN}/open"
}

teardown() {
  # A launcher that failed to stop must not outlive the test (it would hold the
  # runner's output pipe open and hang the whole suite).
  [[ -n "${LAUNCHER_PID:-}" ]] && kill -KILL "${LAUNCHER_PID}" 2>/dev/null || true
  rm -rf "${FAKE_BIN}"
}

# Run a snippet with functions.sh loaded and the stub `open` first on PATH.
_with_functions() {
  PATH="${FAKE_BIN}:${PATH}" DEV_BOT_ROOT="${PROJECT_ROOT}" \
    "${BASH}" -c "source '${PROJECT_ROOT}/src/_shared/functions.sh'; $1"
}

# Start a launcher in the background and set LAUNCHER_PID to the PID of the
# launching shell itself. `exec` matters: without it $! is a wrapper subshell, a
# signal sent to it never reaches the launcher, and the launcher is orphaned.
_start_launcher() {
  ( exec env PATH="${FAKE_BIN}:${PATH}" DEV_BOT_ROOT="${PROJECT_ROOT}" \
      "${BASH}" -c "source '${PROJECT_ROOT}/src/_shared/functions.sh'; $1" ) >/dev/null 2>&1 &
  LAUNCHER_PID=$!
}

# Same as _start_launcher, but keeps the launcher's output in out.log.
_start_launcher_logged() {
  ( exec env PATH="${FAKE_BIN}:${PATH}" DEV_BOT_ROOT="${PROJECT_ROOT}" \
      "${BASH}" -c "source '${PROJECT_ROOT}/src/_shared/functions.sh'; $1" ) >"${FAKE_BIN}/out.log" 2>&1 &
  LAUNCHER_PID=$!
}

# ── _devbot_gui_spec ─────────────────────────────────────────────────────────

@test "_devbot_gui_spec: claudecode opens Claude desktop on the folder" {
  run _with_functions '_devbot_gui_spec claudecode /work/proj; echo "$_DEVBOT_GUI_APP|$_DEVBOT_GUI_BUNDLE_ID|$_DEVBOT_GUI_URL"'
  assert_success
  assert_output "Claude|com.anthropic.claudefordesktop|claude://code/new?folder=%2Fwork%2Fproj"
}

@test "_devbot_gui_spec: opencode opens OpenCode desktop on the folder" {
  run _with_functions '_devbot_gui_spec opencode /work/proj; echo "$_DEVBOT_GUI_APP|$_DEVBOT_GUI_BUNDLE_ID|$_DEVBOT_GUI_URL"'
  assert_success
  assert_output "OpenCode|ai.opencode.desktop|opencode://open-project?directory=%2Fwork%2Fproj"
}

@test "_devbot_gui_spec: percent-encodes spaces and URL metacharacters in the path" {
  run _with_functions '_devbot_gui_spec claudecode "/work/my proj&x=1#frag"; echo "$_DEVBOT_GUI_URL"'
  assert_success
  assert_output "claude://code/new?folder=%2Fwork%2Fmy%20proj%26x%3D1%23frag"
}

@test "_devbot_gui_spec: a harness with no desktop app fails" {
  run _with_functions '_devbot_gui_spec nonesuch /work/proj'
  assert_failure
}

@test "_devbot_gui_spec: only the opencode app carries a limitation note" {
  run _with_functions '_devbot_gui_spec opencode /work/proj; echo "[$_DEVBOT_GUI_NOTE]"'
  assert_success
  assert_output --partial "do not run in the app"
  run _with_functions '_devbot_gui_spec claudecode /work/proj; echo "[$_DEVBOT_GUI_NOTE]"'
  assert_success
  assert_output "[]"
}

# ── _devbot_launch_gui ───────────────────────────────────────────────────────

@test "_devbot_launch_gui: fails clearly when the macOS open command is missing" {
  # PATH holds nothing, so `open` cannot resolve. The shell is invoked by
  # absolute path; the function must fail before reaching for python3.
  PATH="" DEV_BOT_ROOT="${PROJECT_ROOT}" run "${BASH}" -c \
    "source '${PROJECT_ROOT}/src/_shared/functions.sh'; _devbot_launch_gui claudecode /work/proj"
  assert_failure
  assert_output --partial "'open' command"
}

@test "_devbot_launch_gui: reports a missing app and does not hold" {
  # If this wrongly held, bats would hang until the test timeout.
  OPEN_RC=1 run _with_functions '_devbot_launch_gui claudecode /work/proj'
  assert_failure
  assert_output --partial "Claude desktop app not found"
  assert_output --partial "com.anthropic.claudefordesktop"
  assert_output --partial "without --gui"
}

@test "_devbot_launch_gui: addresses the app by bundle id with the deep link" {
  _start_launcher '_devbot_launch_gui opencode "/work/my proj"'
  _wait_for_file "${OPEN_LOG}"
  kill -TERM "${LAUNCHER_PID}"
  wait "${LAUNCHER_PID}" || true

  run cat "${OPEN_LOG}"
  assert_line --index 0 "-b"
  assert_line --index 1 "ai.opencode.desktop"
  assert_line --index 2 "opencode://open-project?directory=%2Fwork%2Fmy%20proj"
}

@test "_devbot_launch_gui: does not hand DEV_BOT_GUI to the app it opens" {
  # `open` forwards its environment to a cold-started app, which passes it to
  # everything it spawns; a leaked DEV_BOT_GUI=1 sends later start.sh runs
  # into the hold loop.
  DEV_BOT_GUI=1 _start_launcher '_devbot_launch_gui claudecode /work/proj'
  _wait_for_file "${OPEN_LOG}"
  kill -TERM "${LAUNCHER_PID}"
  wait "${LAUNCHER_PID}" || true

  run cat "${OPEN_LOG}.gui"
  assert_output "unset"
}

@test "_devbot_launch_gui: warns about the opencode plugin limitation, and not for claudecode" {
  _start_launcher_logged '_devbot_launch_gui opencode /work/proj'
  _wait_for_file "${OPEN_LOG}"
  sleep 1
  kill -TERM "${LAUNCHER_PID}"; wait "${LAUNCHER_PID}" || true
  run cat "${FAKE_BIN}/out.log"
  assert_output --partial "cannot import dev-bot's TypeScript plugins"

  rm -f "${OPEN_LOG}"
  _start_launcher_logged '_devbot_launch_gui claudecode /work/proj'
  _wait_for_file "${OPEN_LOG}"
  sleep 1
  kill -TERM "${LAUNCHER_PID}"; wait "${LAUNCHER_PID}" || true
  run cat "${FAKE_BIN}/out.log"
  refute_output --partial "TypeScript plugins"
}

@test "_devbot_launch_gui: holds after opening, and a TERM releases it cleanly" {
  _start_launcher '_devbot_launch_gui claudecode /work/proj'
  _wait_for_file "${OPEN_LOG}"

  # `open` has returned, yet the launcher must still be alive — otherwise the
  # caller would release the session at once and the services would go down.
  sleep 3
  kill -0 "${LAUNCHER_PID}"

  kill -TERM "${LAUNCHER_PID}"
  local status=0
  wait "${LAUNCHER_PID}" || status=$?
  [ "${status}" -eq 0 ]
}

_wait_for_file() {
  local i
  for i in $(seq 1 100); do
    [[ -s "$1" ]] && return 0
    sleep 0.1
  done
  return 1
}
