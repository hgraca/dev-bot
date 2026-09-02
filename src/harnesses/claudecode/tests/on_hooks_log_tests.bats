#!/usr/bin/env bats
# =============================================================================
# src/harnesses/claudecode/tests/on_hooks_log_tests.bats
# Functional tests for on-hooks.py honoring each hook manifest's "log" field.
#
# Guards audit-31 §5: the startup/stop/post-bash phases called quiet()
# unconditionally, discarding a hook's output even when the manifest declared
# a "log" path. Only the post-file phase (run_file_edits) branched on "log".
# A developer troubleshooting "does the session-start prune actually run?" by
# grepping qmd-index.log saw nothing and wrongly concluded it didn't — the
# self-heal worked, but its evidence trail was broken. All phases must route
# output to the declared log file (mirroring run_file_edits), falling back to
# quiet() only when no log path is declared.
#
# Sandbox pattern (mirrors on_hooks_pre_tool_tests.bats): on-hooks.py computes
# DEV_BOT_ROOT from its own file location (4 levels up from hooks/), so the
# real script is copied into the sandbox at the same relative depth and reads
# manifests from the sandbox's src/agentic tree.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "${TEST_DIR}/../../../.." && pwd)"

  SANDBOX_DIR="$(mktemp -d)"

  command -v python3 &>/dev/null || skip "python3 not installed"
}

teardown() {
  rm -rf "${SANDBOX_DIR}" 2>/dev/null || true
}

# _setup_sandbox: copy on-hooks.py to the sandbox at a depth that makes its
# DEV_BOT_ROOT resolve to the sandbox, then create a fake logging module whose
# script echoes a marker.
_setup_sandbox() {
  mkdir -p "${SANDBOX_DIR}/src/harnesses/claudecode/hooks"
  cp "${PROJECT_ROOT}/src/harnesses/claudecode/hooks/on-hooks.py" \
    "${SANDBOX_DIR}/src/harnesses/claudecode/hooks/on-hooks.py"

  mkdir -p "${SANDBOX_DIR}/src/agentic/fakelog"
  printf '%s\n' '#!/usr/bin/env bash' 'echo "log-marker-ran"' \
    > "${SANDBOX_DIR}/src/agentic/fakelog/log.sh"
  chmod +x "${SANDBOX_DIR}/src/agentic/fakelog/log.sh"
}

# _write_manifest <event> <log-or-empty>: write a single-hook manifest for the
# given event, with a "log" field only when the second arg is non-empty.
_write_manifest() {
  local event="$1"
  local log_field="$2"

  local log_json=""
  if [[ -n "${log_field}" ]]; then
    log_json=", \"log\": \"${log_field}\""
  fi

  cat > "${SANDBOX_DIR}/src/agentic/fakelog/hooks.json" <<JSON
{
  "hooks": [
    {
      "id": "fakelog",
      "event": "${event}",
      "run": ["bash", "{module}/log.sh"]${log_json}
    }
  ]
}
JSON
}

# _run_phase <phase> <stdin-json>: feed a JSON event to on-hooks.py.
_run_phase() {
  local phase="$1"
  local stdin_json="$2"
  printf '%s\n' "${stdin_json}" \
    | python3 "${SANDBOX_DIR}/src/harnesses/claudecode/hooks/on-hooks.py" "${phase}"
}

# ── startup (session.created) ────────────────────────────────────────────────

@test "startup phase honors hook log: output lands in the declared log file" {
  _setup_sandbox
  _write_manifest "session.created" ".agents/logs/fakelog.log"

  run _run_phase startup "{\"cwd\":\"${SANDBOX_DIR}\"}"
  assert_success

  local log="${SANDBOX_DIR}/.agents/logs/fakelog.log"
  assert [ -f "${log}" ]
  run cat "${log}"
  assert_output --partial "fakelog"
  assert_output --partial "log-marker-ran"
}

@test "startup phase without a log field stays quiet (no log file created)" {
  _setup_sandbox
  _write_manifest "session.created" ""

  run _run_phase startup "{\"cwd\":\"${SANDBOX_DIR}\"}"
  assert_success

  refute [ -e "${SANDBOX_DIR}/.agents" ]
}

# ── stop (session.idle) ──────────────────────────────────────────────────────

@test "stop phase honors hook log: output lands in the declared log file" {
  _setup_sandbox
  _write_manifest "session.idle" ".agents/logs/fakelog.log"

  run _run_phase stop "{\"cwd\":\"${SANDBOX_DIR}\",\"session_id\":\"sess-1\"}"
  assert_success

  local log="${SANDBOX_DIR}/.agents/logs/fakelog.log"
  assert [ -f "${log}" ]
  run cat "${log}"
  assert_output --partial "fakelog"
  assert_output --partial "log-marker-ran"
}

# ── post-bash (command.after) ────────────────────────────────────────────────

@test "post-bash phase honors hook log: output lands in the declared log file" {
  _setup_sandbox
  _write_manifest "command.after" ".agents/logs/fakelog.log"

  run _run_phase post-bash \
    "{\"cwd\":\"${SANDBOX_DIR}\",\"tool_input\":{\"command\":\"git commit -m x\"},\"tool_output\":{\"exit_code\":0}}"
  assert_success

  local log="${SANDBOX_DIR}/.agents/logs/fakelog.log"
  assert [ -f "${log}" ]
  run cat "${log}"
  assert_output --partial "fakelog"
  assert_output --partial "log-marker-ran"
}

@test "post-bash phase skips failed commands (exit_code non-zero) and writes no log" {
  _setup_sandbox
  _write_manifest "command.after" ".agents/logs/fakelog.log"

  run _run_phase post-bash \
    "{\"cwd\":\"${SANDBOX_DIR}\",\"tool_input\":{\"command\":\"false\"},\"tool_output\":{\"exit_code\":1}}"
  assert_success

  refute [ -e "${SANDBOX_DIR}/.agents" ]
}
