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
exit 0
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
exit 0
EOF
  chmod +x "${SANDBOX}/src/harnesses/opencode/start.sh"
  cat > "${SANDBOX}/src/harnesses/claudecode/start.sh" <<EOF
#!/usr/bin/env bash
shift || true
printf '%s\n' "start-claudecode" "\$@" > "${SANDBOX}/start-args.log"
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
