#!/usr/bin/env bats
# =============================================================================
# bin/tests/cmd_harness_tests.bats
# Tests for cmd_harness (bin/devbot) harness-arg passthrough: `devbot ... --
# arg-X` must forward only the tail after the first `--` to the harness
# start.sh; no `--` → all args forward. cmd_harness runs the REAL helper
# functions from src/_shared/functions.sh against a sandboxed DEV_BOT_ROOT
# whose up.sh / reinit.sh / harness start.sh are stubs (the real up.sh would
# hit docker).
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../.." && pwd)"

  SANDBOX="$(mktemp -d)"
  mkdir -p "${SANDBOX}/bin" "${SANDBOX}/src/_shared" \
    "${SANDBOX}/src/harnesses/opencode" "${SANDBOX}/src/harnesses/claudecode"

  # Real helpers — cmd_harness depends on _devbot_get_harness /
  # _devbot_auto_reinit_if_config_changed / _devbot_passthrough_args.
  cp "${PROJECT_ROOT}/src/_shared/functions.sh" "${SANDBOX}/src/_shared/functions.sh"
  cp "${PROJECT_ROOT}/src/_shared/read_jsonc.py" "${SANDBOX}/src/_shared/read_jsonc.py"
  # resolve_project.py is the single implementation of the project-first
  # config precedence, and _devbot_get_config delegates to it.
  cp "${PROJECT_ROOT}/src/_shared/resolve_project.py" "${SANDBOX}/src/_shared/resolve_project.py"

  # bin/devbot without the `main "$@"` tail — sourced so cmd_harness is
  # callable directly (same pattern as init_tests.bats).
  sed '/^main "\$@"/d' "${PROJECT_ROOT}/bin/devbot" > "${SANDBOX}/bin/devbot"

  # Stub up.sh — the real one starts docker services. Also records whether a
  # session file already exists at up-time (proves register runs BEFORE up).
  cat > "${SANDBOX}/bin/up.sh" <<EOF
#!/usr/bin/env bash
echo "up-called"
local_files="\$(find "${SANDBOX}/storage/run/sessions" -maxdepth 1 -name 'session-*' 2>/dev/null | wc -l | tr -d ' ')"
echo "sessions-at-up=\${local_files}" >> "${SANDBOX}/up.log"
exit "\${UP_RC:-0}"
EOF
  chmod +x "${SANDBOX}/bin/up.sh"

  # Stub down.sh — the session registry's last-exit teardown delegates here.
  cat > "${SANDBOX}/bin/down.sh" <<EOF
#!/usr/bin/env bash
echo "down-called" >> "${SANDBOX}/down.log"
exit 0
EOF
  chmod +x "${SANDBOX}/bin/down.sh"

  # Mock docker so _devbot_session_teardown's \`docker info\` guard passes.
  mkdir -p "${SANDBOX}/mockbin"
  cat > "${SANDBOX}/mockbin/docker" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${SANDBOX}/mockbin/docker"
  export PATH="${SANDBOX}/mockbin:${PATH}"

  # Stub reinit.sh — the real one runs reset+init (a mutation the audit forbids
  # and a heavy flow for a wiring test). Records the invocation; refreshes the
  # .sha baselines the way a real reinit does (it ends by running init.sh,
  # which writes them), so a second cmd_harness call would no-op. Runs from
  # the project dir (cmd_harness cd's there before invoking it), so $(pwd) is
  # the project and DEV_BOT_ROOT is the sandbox.
  cat > "${SANDBOX}/bin/reinit.sh" <<'REINIT_EOF'
#!/usr/bin/env bash
source "${DEV_BOT_ROOT}/src/_shared/functions.sh"
echo "reinit-called $(pwd)" >> "${DEV_BOT_ROOT}/reinit.log"
_devbot_write_config_sha "$(pwd)"
exit 0
REINIT_EOF
  chmod +x "${SANDBOX}/bin/reinit.sh"

  # Stub update.sh — the real one hits the network. Records the auto-update
  # invocation; exits with UPDATE_RC (default 0).
  cat > "${SANDBOX}/bin/update.sh" <<EOF
#!/usr/bin/env bash
echo "update-called \$*" >> "${SANDBOX}/update.log"
exit "\${UPDATE_RC:-0}"
EOF
  chmod +x "${SANDBOX}/bin/update.sh"

  # Stub harness start.sh — mirrors the real one: shifts off the project
  # dir (its first arg) and records the harness argv it received.
  cat > "${SANDBOX}/src/harnesses/opencode/start.sh" <<EOF
#!/usr/bin/env bash
shift || true
printf '%s\n' "start-opencode" "\$@" > "${SANDBOX}/start-args.log"
echo "gui=\${DEV_BOT_GUI:-unset}" > "${SANDBOX}/start-env.log"
exit 0
EOF
  chmod +x "${SANDBOX}/src/harnesses/opencode/start.sh"
  cat > "${SANDBOX}/src/harnesses/claudecode/start.sh" <<EOF
#!/usr/bin/env bash
shift || true
printf '%s\n' "start-claudecode" "\$@" > "${SANDBOX}/start-args.log"
echo "gui=\${DEV_BOT_GUI:-unset}" > "${SANDBOX}/start-env.log"
exit 0
EOF
  chmod +x "${SANDBOX}/src/harnesses/claudecode/start.sh"

  # Global config with auto_update off (these are wiring tests, not update
  # tests) + a matching per-project wiring baseline → auto-reinit no-ops.
  echo '{"auto_update": false}' > "${SANDBOX}/.devbot.global.jsonc"

  # Project dir: opencode harness chosen explicitly.
  PROJECT="$(mktemp -d)"
  echo '{"harness": "opencode"}' > "${PROJECT}/.devbot.project.jsonc"
  _write_baseline
}

teardown() {
  # A --gui devbot that failed to stop must not outlive the test.
  [[ -n "${GUI_DEVBOT_PID:-}" ]] && kill -KILL "${GUI_DEVBOT_PID}" 2>/dev/null || true
  rm -rf "${SANDBOX}" "${PROJECT}" 2>/dev/null || true
}

# Refresh the per-project combined wiring baseline (what init.sh writes).
_write_baseline() {
  python3 - "${SANDBOX}/.devbot.global.jsonc" "${PROJECT}/.devbot.project.jsonc" \
    > "${PROJECT}/.devbot.project.sha" <<'PY'
import hashlib
import sys

h = hashlib.sha256()
for i, path in enumerate(sys.argv[1:]):
    if i:
        h.update(b"\0")
    h.update(open(path, "rb").read())
print(h.hexdigest())
PY
}

# Source the sandboxed devbot and run cmd_harness from the project dir.
_run_cmd_harness() {
  cd "${PROJECT}"
  DEV_BOT_ROOT="${SANDBOX}" run bash -c "
    source '${SANDBOX}/bin/devbot'
    cmd_harness \"\$@\"
  " _ "$@"
  cd "${PROJECT_ROOT}"
}

@test "cmd_harness reports a failed up instead of exiting silently" {
  # The EXIT trap tears the containers down and suppresses its own message on a
  # failed start, so without this line the user sees the teardown and nothing
  # about the cause.
  export UP_RC=3
  rm -f "${SANDBOX}/start-args.log"

  _run_cmd_harness

  unset UP_RC
  assert_failure 3
  assert_output --partial "devbot up failed (exit 3)"
  assert_output --partial "torn down on exit"
  [ ! -f "${SANDBOX}/start-args.log" ]
}

@test "cmd_harness forwards all args unchanged when no -- is present" {
  rm -f "${SANDBOX}/start-args.log"
  _run_cmd_harness -c "two words"
  assert_success
  assert_output --partial "up-called"
  run cat "${SANDBOX}/start-args.log"
  assert_line --index 0 "start-opencode"
  assert_line --index 1 "-c"
  assert_line --index 2 "two words"
}

@test "cmd_harness forwards only the tail after -- to the harness" {
  rm -f "${SANDBOX}/start-args.log"
  _run_cmd_harness run "task" -- -c "two words"
  assert_success
  run cat "${SANDBOX}/start-args.log"
  assert_line --index 0 "start-opencode"
  assert_line --index 1 "-c"
  assert_line --index 2 "two words"
  # The pre-`--` tokens (run, task) are devbot's own — never reach start.sh.
  refute_line "run"
  refute_line "task"
}

@test "cmd_harness forwards --help after a leading -- to the harness" {
  rm -f "${SANDBOX}/start-args.log"
  _run_cmd_harness -- --help
  assert_success
  run cat "${SANDBOX}/start-args.log"
  assert_line --index 0 "start-opencode"
  assert_line --index 1 "--help"
}

@test "cmd_harness sends no harness args for a bare --" {
  rm -f "${SANDBOX}/start-args.log"
  _run_cmd_harness --
  assert_success
  run cat "${SANDBOX}/start-args.log"
  assert_line --index 0 "start-opencode"
  # No further lines — empty harness argv.
  [ "$(wc -l < "${SANDBOX}/start-args.log")" -eq 1 ]
}

# ── --gui: open the desktop app instead of the harness CLI ────────────────────

@test "cmd_harness --gui is consumed and signals GUI mode to start.sh" {
  rm -f "${SANDBOX}/start-args.log" "${SANDBOX}/start-env.log"
  _run_cmd_harness --gui
  assert_success
  assert_output --partial "up-called"
  run cat "${SANDBOX}/start-args.log"
  assert_line --index 0 "start-opencode"
  # --gui is devbot's own flag — the harness never sees it.
  refute_line "--gui"
  [ "$(wc -l < "${SANDBOX}/start-args.log")" -eq 1 ]
  run cat "${SANDBOX}/start-env.log"
  assert_output "gui=1"
}

@test "cmd_harness --gui routes to the claudecode harness when configured" {
  echo '{"harness": "claudecode"}' > "${PROJECT}/.devbot.project.jsonc"
  _write_baseline
  rm -f "${SANDBOX}/start-args.log" "${SANDBOX}/start-env.log"
  _run_cmd_harness --gui
  assert_success
  run cat "${SANDBOX}/start-args.log"
  assert_line --index 0 "start-claudecode"
  run cat "${SANDBOX}/start-env.log"
  assert_output "gui=1"
}

@test "cmd_harness without --gui leaves GUI mode off, even if DEV_BOT_GUI is already set" {
  rm -f "${SANDBOX}/start-env.log"
  DEV_BOT_GUI=1 _run_cmd_harness
  assert_success
  run cat "${SANDBOX}/start-env.log"
  assert_output "gui=unset"
}

@test "cmd_harness --gui with harness args is refused before anything starts" {
  rm -f "${SANDBOX}/start-args.log" "${SANDBOX}/up.log"
  _run_cmd_harness --gui -- -c "msg"
  assert_failure
  assert_output --partial "harness arguments are not supported"
  # Refused up front: no docker services started, no harness launched.
  refute_output --partial "up-called"
  [ ! -f "${SANDBOX}/start-args.log" ]
  [ ! -f "${SANDBOX}/up.log" ]
}

@test "cmd_harness --gui refuses unforwardable flags rather than dropping them" {
  rm -f "${SANDBOX}/start-args.log"
  _run_cmd_harness --gui -c
  assert_failure
  assert_output --partial "harness arguments are not supported"
  [ ! -f "${SANDBOX}/start-args.log" ]
}

@test "cmd_harness --gui with a bare -- is allowed (empty harness tail)" {
  rm -f "${SANDBOX}/start-env.log"
  _run_cmd_harness --gui --
  assert_success
  run cat "${SANDBOX}/start-env.log"
  assert_output "gui=1"
}

@test "cmd_harness treats --gui after the -- separator as a literal harness arg" {
  rm -f "${SANDBOX}/start-args.log" "${SANDBOX}/start-env.log"
  _run_cmd_harness -- --gui
  assert_success
  run cat "${SANDBOX}/start-args.log"
  assert_line --index 1 "--gui"
  run cat "${SANDBOX}/start-env.log"
  assert_output "gui=unset"
}

# A --gui start.sh holds after opening the app (see _devbot_launch_gui) and only
# stops on a signal delivered to ITS OWN process. A bare `kill -TERM <devbot>`
# is not delivered to a foreground child, so cmd_harness must forward it —
# these tests signal devbot's PID alone, exactly like `kill <pid>` from another
# terminal. The stub mirrors the real hold loop.

_start_gui_holding() {
  rm -f "${SANDBOX}/down.log" "${SANDBOX}/holding"
  cat > "${SANDBOX}/src/harnesses/opencode/start.sh" <<EOF
#!/usr/bin/env bash
touch "${SANDBOX}/holding"
stop=0
trap 'stop=1' INT TERM
while [[ "\${stop}" -eq 0 ]]; do sleep 1; done
exit 0
EOF
  chmod +x "${SANDBOX}/src/harnesses/opencode/start.sh"

  # `exec` so $! is the devbot shell itself, not a wrapper subshell.
  ( cd "${PROJECT}" && exec env DEV_BOT_ROOT="${SANDBOX}" "${BASH}" -c "
      source '${SANDBOX}/bin/devbot'
      cmd_harness --gui
    " ) >/dev/null 2>&1 &
  GUI_DEVBOT_PID=$!

  local i
  for i in $(seq 1 100); do
    [[ -f "${SANDBOX}/holding" ]] && return 0
    sleep 0.1
  done
  kill -KILL "${GUI_DEVBOT_PID}" 2>/dev/null || true
  return 1
}

# Wait up to ~8s for GUI_DEVBOT_PID to exit; kill it and fail when it does not,
# so a regression cannot hang the suite. Sets GUI_STATUS.
_wait_gui_exit() {
  local i
  for i in $(seq 1 80); do
    kill -0 "${GUI_DEVBOT_PID}" 2>/dev/null || { GUI_STATUS=0; wait "${GUI_DEVBOT_PID}" || GUI_STATUS=$?; return 0; }
    sleep 0.1
  done
  kill -KILL "${GUI_DEVBOT_PID}" 2>/dev/null || true
  return 1
}

@test "cmd_harness --gui: a direct TERM to devbot ends the hold and releases the session" {
  _start_gui_holding
  kill -TERM "${GUI_DEVBOT_PID}"
  _wait_gui_exit
  # The hold stopped on request, so this is a clean exit — not 143.
  [ "${GUI_STATUS}" -eq 0 ]
  [ -f "${SANDBOX}/down.log" ]
  run cat "${SANDBOX}/down.log"
  assert_output "down-called"
}

# There is deliberately no "direct INT" test: a process started in the
# background of a non-interactive shell (which is what a test must do to signal
# it) has SIGINT ignored from the start, and bash cannot trap a signal that was
# ignored on entry. A real Ctrl-C reaches a foreground devbot, and the INT trap
# is the same one TERM exercises above.

@test "cmd_harness --gui: leaves no hold process behind after TERM" {
  _start_gui_holding
  local hold_pid
  hold_pid="$(pgrep -P "${GUI_DEVBOT_PID}" | head -1)"
  [ -n "${hold_pid}" ]
  kill -TERM "${GUI_DEVBOT_PID}"
  _wait_gui_exit
  sleep 1.5
  ! kill -0 "${hold_pid}" 2>/dev/null
}

# ── cmd_models: routes through _devbot_ollama_exec (boot→operate→down) ─────
# _devbot_ollama_exec itself is unit-tested in ollama_exec_tests.bats; here we
# stub it to record argv and assert cmd_models dispatches pull/list-local/
# remove to it with the right ollama subcommand. list-remote stays non-booting
# (registry browsing — its local-cache reference line degrades to "(none)").

_run_cmd_models() {
  DEV_BOT_ROOT="${SANDBOX}" run bash -c "
    source '${SANDBOX}/bin/devbot'
    _devbot_ollama_exec() { printf 'exec:%s\n' \"\$*\" > '${SANDBOX}/models-calls.log'; }
    cmd_models \"\$@\"
  " _ "$@"
}

@test "cmd_models pull routes to _devbot_ollama_exec pull" {
  rm -f "${SANDBOX}/models-calls.log"
  _run_cmd_models pull llama3.2:3b
  assert_success
  run cat "${SANDBOX}/models-calls.log"
  assert_output "exec:pull llama3.2:3b"
}

@test "cmd_models list-local routes to _devbot_ollama_exec list" {
  rm -f "${SANDBOX}/models-calls.log"
  _run_cmd_models list-local
  assert_success
  run cat "${SANDBOX}/models-calls.log"
  assert_output "exec:list"
}

@test "cmd_models remove routes to _devbot_ollama_exec rm" {
  rm -f "${SANDBOX}/models-calls.log"
  _run_cmd_models remove llama3.2:3b
  assert_success
  run cat "${SANDBOX}/models-calls.log"
  assert_output "exec:rm llama3.2:3b"
}

@test "cmd_harness runs reinit before up when the project config changed (stale baseline)" {
  rm -f "${SANDBOX}/reinit.log" "${SANDBOX}/start-args.log"
  # Make the project config differ from its stored .sha → auto-reinit fires.
  echo '{"harness": "opencode", "project_name": "edited"}' > "${PROJECT}/.devbot.project.jsonc"

  _run_cmd_harness -c "two words"
  # Copy status/output BEFORE any later `run` overwrites them.
  local harness_status="${status}" harness_output="${output}"
  assert_success
  # reinit ran BEFORE up.sh (the whole point of gap 1).
  run cat "${SANDBOX}/reinit.log"
  assert_output "reinit-called ${PROJECT}"
  # And up still ran afterwards, then start.sh got the passthrough args.
  [[ "${harness_output}" == *"up-called"* ]]
  run cat "${SANDBOX}/start-args.log"
  assert_line --index 0 "start-opencode"
  assert_line --index 1 "-c"
  assert_line --index 2 "two words"
}

@test "cmd_harness reinits at most once — a refreshed baseline no-ops the next start" {
  rm -f "${SANDBOX}/reinit.log" "${SANDBOX}/start-args.log"
  echo '{"harness": "opencode", "project_name": "edited"}' > "${PROJECT}/.devbot.project.jsonc"

  # First start: stale → reinit fires and refreshes baselines.
  _run_cmd_harness
  assert_success
  run cat "${SANDBOX}/reinit.log"
  assert_output --partial "reinit-called"

  # Second start: baselines now match → no second reinit.
  rm -f "${SANDBOX}/reinit.log"
  _run_cmd_harness
  assert_success
  [ ! -e "${SANDBOX}/reinit.log" ]
}

# ── Auto-update on start ─────────────────────────────────────────────────────

@test "cmd_harness auto-runs update --auto before wiring when auto_update is on" {
  rm -f "${SANDBOX}/update.log" "${SANDBOX}/start-args.log"
  echo '{"auto_update": true}' > "${SANDBOX}/.devbot.global.jsonc"
  _write_baseline # keep the reinit quiet

  _run_cmd_harness
  assert_success
  run cat "${SANDBOX}/update.log"
  assert_output "update-called --auto"
}

@test "cmd_harness skips auto-update when auto_update is false" {
  rm -f "${SANDBOX}/update.log" "${SANDBOX}/start-args.log"

  _run_cmd_harness
  assert_success
  [ ! -e "${SANDBOX}/update.log" ]
}

@test "a failed auto-update warns and the start still proceeds" {
  rm -f "${SANDBOX}/update.log" "${SANDBOX}/start-args.log"
  echo '{"auto_update": true}' > "${SANDBOX}/.devbot.global.jsonc"
  _write_baseline

  export UPDATE_RC=1
  _run_cmd_harness
  local out="${output}"
  unset UPDATE_RC

  assert_success
  [[ "${out}" == *"auto-update failed"* ]]
  [[ "${out}" == *"up-called"* ]]
}

# ── Session registry: last-exit tears containers down ────────────────────────
# cmd_harness registers a session before up.sh and releases after start.sh
# returns; when it was the last session, the registry runs bin/down.sh.

@test "cmd_harness tears containers down when the session was the last" {
  rm -f "${SANDBOX}/down.log" "${SANDBOX}/start-args.log"
  _run_cmd_harness
  assert_success
  # No live sessions remain → down called on exit.
  [ -f "${SANDBOX}/down.log" ]
  run cat "${SANDBOX}/down.log"
  assert_output "down-called"
}

@test "a failed start tears containers down without claiming the session ended" {
  rm -f "${SANDBOX}/down.log" "${SANDBOX}/start-args.log"
  # up.sh fails (e.g. `docker compose up` returned non-zero).
  cat > "${SANDBOX}/bin/up.sh" <<'EOF'
#!/usr/bin/env bash
echo "ERROR: docker compose up failed" >&2
exit 1
EOF
  chmod +x "${SANDBOX}/bin/up.sh"

  _run_cmd_harness

  assert_failure
  # Cleanup still runs — half-started containers must not linger...
  [ -f "${SANDBOX}/down.log" ]
  # ...but the last-session message must stay quiet: after a failed start it
  # reads as the CAUSE of the failure rather than its consequence.
  refute_output --partial "Last devbot session ended"
  # And the harness is never started.
  [ ! -f "${SANDBOX}/start-args.log" ]
}

@test "cmd_harness leaves containers up when another session is live" {
  rm -f "${SANDBOX}/down.log" "${SANDBOX}/start-args.log"
  # A concurrent live session: hold a flock on a session file for the duration.
  mkdir -p "${SANDBOX}/storage/run/sessions"
  ( exec 215>"${SANDBOX}/storage/run/sessions/session-99999"; flock -x 215; sleep 3 ) &
  local holder=$!
  sleep 0.3

  _run_cmd_harness
  assert_success
  # Another session is still live → no teardown.
  [ ! -f "${SANDBOX}/down.log" ]

  kill "${holder}" 2>/dev/null || true
}

@test "cmd_harness registers before up.sh and removes its session file on exit" {
  rm -f "${SANDBOX}/down.log" "${SANDBOX}/up.log"
  _run_cmd_harness
  assert_success
  # register ran BEFORE up.sh: the session file existed when up.sh executed.
  run cat "${SANDBOX}/up.log"
  assert_output "sessions-at-up=1"
  # And release unlinked this session's own file on exit.
  local remaining
  remaining="$(find "${SANDBOX}/storage/run/sessions" -maxdepth 1 -name 'session-*' 2>/dev/null | wc -l | tr -d ' ')"
  [ "${remaining}" -eq 0 ]
}

# ── Signal handling: Ctrl-C (SIGINT) also releases the session ───────────────
# EXIT traps do NOT fire on SIGINT, so cmd_harness traps INT TERM EXIT. This
# runs cmd_harness as a foreground child (timeout -s INT delivers SIGINT to
# its group, like Ctrl-C) and asserts the last-exit teardown still ran.
# A harness stub that sleeps keeps the session alive until the signal.

@test "SIGINT releases the session and tears containers down" {
  rm -f "${SANDBOX}/down.log" "${SANDBOX}/start-args.log"
  cat > "${SANDBOX}/src/harnesses/opencode/start.sh" <<EOF
#!/usr/bin/env bash
shift || true
printf '%s\n' "start-opencode" "\$@" > "${SANDBOX}/start-args.log"
sleep 30
EOF
  chmod +x "${SANDBOX}/src/harnesses/opencode/start.sh"

  # timeout sends SIGINT to the command's process group after 2s (Ctrl-C-like).
  cd "${PROJECT}"
  DEV_BOT_ROOT="${SANDBOX}" run timeout -s INT 2 bash -c "
    source '${SANDBOX}/bin/devbot'
    cmd_harness
  "
  cd "${PROJECT_ROOT}"
  # timeout reports 124 when it had to signal — that's expected, not a failure.
  sleep 0.5
  [ -f "${SANDBOX}/down.log" ]
  run cat "${SANDBOX}/down.log"
  assert_output "down-called"
}

# ── Start refusal outside an initialised project ────────────────────────────
# A bare `devbot` in a folder that was never initialised must say so and point
# at `devbot init`; it must not fall through to up.sh and the harness.

@test "cmd_harness refuses to start a folder that was never initialised" {
  local bare
  bare="$(mktemp -d)"

  cd "${bare}"
  DEV_BOT_ROOT="${SANDBOX}" run bash -c "
    source '${SANDBOX}/bin/devbot'
    cmd_harness
  "
  cd "${PROJECT_ROOT}"
  rmdir "${bare}"

  assert_failure
  assert_output --partial "devbot init"
  refute_output --partial "up-called"
}

# ── Exit epilogue: the devbot continuation line ──────────────────────────────
# opencode prints its own epilogue on exit (logo, `Session <title>`, `Continue
# opencode -s <id>`). devbot adds ONE line with its own command, so the hint
# names the tool the user is actually in. The id cannot be known before launch
# — the child creates the session — so it is read afterwards, from the
# project-scoped `session list --format json` (newest first, already used by
# bin/prune.sh).

# Source the sandboxed devbot, force the terminal gate on (bats captures stdout,
# so a real [ -t 1 ] would never fire here), then run cmd_harness. HOME defaults
# to a sandbox path so the v1 branch cannot reach this machine's ~/.opencode;
# a test needing its own home sets EPILOGUE_HOME.
_run_cmd_harness_epilogue() {
  cd "${PROJECT}"
  DEV_BOT_ROOT="${SANDBOX}" HOME="${EPILOGUE_HOME:-${SANDBOX}/home}" run bash -c "
    source '${SANDBOX}/bin/devbot'
    _devbot_epilogue_enabled() { return 0; }
    cmd_harness \"\$@\"
  " _ "$@"
  cd "${PROJECT_ROOT}"
}

# Stub the harness binary a real v1 launcher runs, answering
# `session list --format json` with <json>. It lives at the launcher's own path
# (~/.opencode/bin/opencode) because the v1 branch probes nothing else.
_stub_opencode_raw() {
  mkdir -p "${SANDBOX}/home/.opencode/bin"
  cat > "${SANDBOX}/home/.opencode/bin/opencode" <<EOF
#!/usr/bin/env bash
printf '%s\n' '$1'
EOF
  chmod +x "${SANDBOX}/home/.opencode/bin/opencode"
}

# Stub the listing with one session updated at <updated_ms>, so a test can date
# it before the launch.
_stub_opencode_session() {
  local updated_ms="$1" id="${2:-ses_TEST123}" title="${3:-Test session}"
  _stub_opencode_raw "[{\"id\":\"${id}\",\"title\":\"${title}\",\"updated\":${updated_ms},\"created\":${updated_ms},\"projectId\":\"p\",\"directory\":\"${PROJECT}\"}]"
}

@test "cmd_harness offers the devbot command for the session just ended" {
  _stub_opencode_session "$(( $(date +%s) * 1000 ))"
  _run_cmd_harness_epilogue
  assert_success
  assert_output --partial "devbot -- -s ses_TEST123"
}

@test "cmd_harness prints no continuation line when the harness left no session" {
  _stub_opencode_raw '[]'

  _run_cmd_harness_epilogue
  assert_success
  refute_output --partial "Continue"
}

@test "cmd_harness stays quiet when stdout is not a terminal" {
  _stub_opencode_session "$(( $(date +%s) * 1000 ))"
  # No override: bats captures stdout through a pipe, so the gate is closed.
  _run_cmd_harness
  assert_success
  refute_output --partial "Continue"
}

@test "cmd_harness does not offer a session older than this launch" {
  # `devbot -- --help` exits without touching a session: the newest row predates
  # the launch and is not the session the user just sat in.
  _stub_opencode_session 1000
  _run_cmd_harness_epilogue
  assert_success
  refute_output --partial "Continue"
}

@test "cmd_harness offers claude --resume for the session just ended" {
  echo '{"harness": "claudecode"}' > "${PROJECT}/.devbot.project.jsonc"
  _write_baseline

  local home="${SANDBOX}/fakehome" slug uuid
  uuid="11111111-2222-3333-4444-555555555555"
  slug="$(printf '%s' "${PROJECT}" | sed 's/[^A-Za-z0-9]/-/g')"
  mkdir -p "${home}/.claude/projects/${slug}"
  : > "${home}/.claude/projects/${slug}/${uuid}.jsonl"

  EPILOGUE_HOME="${home}" _run_cmd_harness_epilogue
  assert_success
  assert_output --partial "devbot -- --resume ${uuid}"
}

@test "cmd_harness honours CLAUDE_PROJECTS_DIR for the transcript root" {
  echo '{"harness": "claudecode"}' > "${PROJECT}/.devbot.project.jsonc"
  _write_baseline

  local root="${SANDBOX}/claude-projects" slug uuid
  uuid="22222222-3333-4444-5555-666666666666"
  slug="$(printf '%s' "${PROJECT}" | sed 's/[^A-Za-z0-9]/-/g')"
  mkdir -p "${root}/${slug}"
  : > "${root}/${slug}/${uuid}.jsonl"

  CLAUDE_PROJECTS_DIR="${root}" EPILOGUE_HOME="${SANDBOX}/empty-home" \
    _run_cmd_harness_epilogue
  assert_success
  assert_output --partial "devbot -- --resume ${uuid}"
}

@test "cmd_harness honours CLAUDE_CONFIG_DIR's projects folder" {
  echo '{"harness": "claudecode"}' > "${PROJECT}/.devbot.project.jsonc"
  _write_baseline

  local config="${SANDBOX}/claude-config" slug uuid
  uuid="33333333-4444-5555-6666-777777777777"
  slug="$(printf '%s' "${PROJECT}" | sed 's/[^A-Za-z0-9]/-/g')"
  mkdir -p "${config}/projects/${slug}"
  : > "${config}/projects/${slug}/${uuid}.jsonl"

  CLAUDE_CONFIG_DIR="${config}" EPILOGUE_HOME="${SANDBOX}/empty-home" \
    _run_cmd_harness_epilogue
  assert_success
  assert_output --partial "devbot -- --resume ${uuid}"
}

@test "cmd_harness still offers a session written within the grace window" {
  # The launch stamp is truncated to the second, so a session touched in the
  # second before it must not read as stale.
  _stub_opencode_session "$(( $(date +%s) * 1000 - 1000 ))"
  _run_cmd_harness_epilogue
  assert_success
  assert_output --partial "devbot -- -s ses_TEST123"
}

@test "cmd_harness prints nothing when the session listing fails" {
  mkdir -p "${SANDBOX}/home/.opencode/bin"
  cat > "${SANDBOX}/home/.opencode/bin/opencode" <<'EOF'
#!/usr/bin/env bash
echo 'opencode: unexpected failure'
exit 1
EOF
  chmod +x "${SANDBOX}/home/.opencode/bin/opencode"

  _run_cmd_harness_epilogue
  assert_success
  refute_output --partial "Continue"
}

@test "cmd_harness prints nothing when the harness binary is gone" {
  _stub_opencode_session "$(( $(date +%s) * 1000 ))"
  # The launcher runs ${HOME}/.opencode/bin/opencode and nothing else, so a home
  # without it means no session ran — even with an opencode elsewhere on PATH.
  EPILOGUE_HOME="${SANDBOX}/empty-home" _run_cmd_harness_epilogue
  assert_success
  refute_output --partial "Continue"
}

@test "cmd_harness never reads a session from an opencode that did not run" {
  # The v1 launcher runs only ${HOME}/.opencode/bin/opencode. An opencode found
  # elsewhere on PATH belongs to another install, so its id must not surface.
  mkdir -p "${SANDBOX}/mockbin"
  cat > "${SANDBOX}/mockbin/opencode" <<EOF
#!/usr/bin/env bash
printf '%s\n' '[{"id":"ses_DECOY","title":"other install","updated":$(( $(date +%s) * 1000 )),"directory":"${PROJECT}"}]'
EOF
  chmod +x "${SANDBOX}/mockbin/opencode"

  EPILOGUE_HOME="${SANDBOX}/empty-home" _run_cmd_harness_epilogue
  assert_success
  refute_output --partial "Continue"
}

@test "cmd_harness renders the continuation line with real escape bytes" {
  # TEXT_* hold the literal \033 sequence and only `echo -e` expands it, so a
  # printf-based printer shows escape noise on a real terminal. bats pipes
  # stdout, so this test forces colour on to see what a TTY would get.
  _stub_opencode_session "$(( $(date +%s) * 1000 ))"
  FORCE_COLOR=1 _run_cmd_harness_epilogue
  assert_success

  local esc
  esc="$(printf '\033')"
  [[ "${output}" == *"${esc}[2m"* ]]
  [[ "${output}" == *"${esc}[1m"* ]]
  refute_output --partial '\033'
}

@test "cmd_harness prefers a session recorded for this directory" {
  # The listing is project-scoped, so a sibling checkout can lead it. Filtering
  # on the row's own `directory` is what keeps the hint on this session.
  _stub_opencode_raw "[{\"id\":\"ses_OTHER\",\"title\":\"sibling\",\"updated\":$(( $(date +%s) * 1000 )),\"directory\":\"/some/sibling\"},{\"id\":\"ses_HERE\",\"title\":\"this one\",\"updated\":$(( $(date +%s) * 1000 - 1000 )),\"directory\":\"${PROJECT}\"}]"

  _run_cmd_harness_epilogue
  assert_success
  assert_output --partial "devbot -- -s ses_HERE"
  refute_output --partial "ses_OTHER"
}

@test "cmd_harness offers nothing when every row belongs to another checkout" {
  # A fresh sibling session is not evidence of a session here: with no matching
  # directory there is no session to offer, however recent the row is.
  _stub_opencode_raw "[{\"id\":\"ses_OTHER\",\"title\":\"sibling\",\"updated\":$(( $(date +%s) * 1000 )),\"directory\":\"/some/sibling\"}]"

  _run_cmd_harness_epilogue
  assert_success
  refute_output --partial "Continue"
}

@test "cmd_harness uses a listing whose rows carry no directory" {
  # Older payloads omit the field; nothing can be attributed, so the newest row
  # is the best answer available.
  _stub_opencode_raw "[{\"id\":\"ses_NODIR\",\"title\":\"no directory\",\"updated\":$(( $(date +%s) * 1000 ))}]"

  _run_cmd_harness_epilogue
  assert_success
  assert_output --partial "devbot -- -s ses_NODIR"
}

@test "the claudecode slug maps a literal project path" {
  # Pinned against a literal path so a changed transform fails here, instead of
  # being recomputed by the same rule the implementation uses.
  local home="${SANDBOX}/slug-home" since
  mkdir -p "${home}/.claude/projects/-fixed-path--with-dots"
  : > "${home}/.claude/projects/-fixed-path--with-dots/abc.jsonl"
  since="$(( $(date +%s) * 1000 ))"

  DEV_BOT_ROOT="${SANDBOX}" HOME="${home}" run bash -c "
    source '${SANDBOX}/src/_shared/functions.sh'
    _devbot_last_session claudecode /fixed/path/.with.dots ${since}
  "
  assert_output "abc"
}

@test "cmd_harness offers the devbot command for an opencode-v2 session" {
  echo '{"harness": "opencode-v2"}' > "${PROJECT}/.devbot.project.jsonc"
  _write_baseline
  mkdir -p "${SANDBOX}/src/harnesses/opencode-v2"
  cat > "${SANDBOX}/src/harnesses/opencode-v2/functions.sh" <<EOF
_devbot_opencode2_bin() { printf '%s' "${SANDBOX}/home/.opencode/bin/opencode"; }
EOF
  cat > "${SANDBOX}/src/harnesses/opencode-v2/start.sh" <<EOF
#!/usr/bin/env bash
shift || true
printf '%s\n' "start-opencode-v2" "\$@" > "${SANDBOX}/start-args.log"
exit 0
EOF
  chmod +x "${SANDBOX}/src/harnesses/opencode-v2/start.sh"
  _stub_opencode_session "$(( $(date +%s) * 1000 ))"

  _run_cmd_harness_epilogue
  assert_success
  assert_output --partial "devbot -- -s ses_TEST123"
}
