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

  # Stub up.sh — the real one starts docker services.
  cat > "${SANDBOX}/bin/up.sh" <<'EOF'
#!/usr/bin/env bash
echo "up-called"
exit 0
EOF
  chmod +x "${SANDBOX}/bin/up.sh"

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

  # Global config + matching .sha baseline → auto-reinit no-ops (the reinit
  # would otherwise fire and need its own stub).
  echo '{}' > "${SANDBOX}/.devbot.global.jsonc"
  python3 -c "
import hashlib
print(hashlib.sha256(open('${SANDBOX}/.devbot.global.jsonc','rb').read()).hexdigest())
" > "${SANDBOX}/.devbot.global.sha"

  # Project dir: opencode harness chosen explicitly.
  PROJECT="$(mktemp -d)"
  echo '{"harness": "opencode"}' > "${PROJECT}/.devbot.project.jsonc"
  python3 -c "
import hashlib
print(hashlib.sha256(open('${PROJECT}/.devbot.project.jsonc','rb').read()).hexdigest())
" > "${PROJECT}/.devbot.project.sha"
}

teardown() {
  rm -rf "${SANDBOX}" "${PROJECT}" 2>/dev/null || true
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
