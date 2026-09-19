#!/usr/bin/env bats
# =============================================================================
# src/harnesses/claudecode/tests/on_hooks_env_tests.bats
# on-hooks.py publishes DEV_BOT_SESSION_ID and DEV_BOT_AGENT_NAME to the Bash
# preamble via $CLAUDE_ENV_FILE.
#
# Claude Code exports no session-id env var to the shell (upstream issue 47018),
# and a tool-event payload carries agent_type only inside a subagent — so the
# adapter writes both assignments to the preamble file, which Claude Code runs
# before every Bash command. This is the claudecode counterpart of opencode's
# shell.env hook.
#
# Sandbox pattern (mirrors on_hooks_pre_tool_tests.bats): on-hooks.py computes
# DEV_BOT_ROOT from its own file location, so the real script is copied into the
# sandbox at the same relative depth.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "${TEST_DIR}/../../../.." && pwd)"

  SANDBOX_DIR="$(mktemp -d)"
  PREAMBLE="${SANDBOX_DIR}/env-preamble.sh"
  export CLAUDE_ENV_FILE="${PREAMBLE}"

  command -v python3 &>/dev/null || skip "python3 not installed"
}

teardown() {
  rm -rf "${SANDBOX_DIR}" 2>/dev/null || true
}

# _setup_sandbox: copy on-hooks.py to the sandbox at a depth that makes its
# DEV_BOT_ROOT resolve to the sandbox, and give it a manifest root to read.
_setup_sandbox() {
  mkdir -p "${SANDBOX_DIR}/src/harnesses/claudecode/hooks"
  cp "${PROJECT_ROOT}/src/harnesses/claudecode/hooks/on-hooks.py" \
    "${SANDBOX_DIR}/src/harnesses/claudecode/hooks/on-hooks.py"
  mkdir -p "${SANDBOX_DIR}/src/agentic"
}

# _run_phase <phase> <json>: feed a hook event to the sandboxed dispatcher.
_run_phase() {
  printf '%s\n' "$2" \
    | python3 "${SANDBOX_DIR}/src/harnesses/claudecode/hooks/on-hooks.py" "$1"
}

@test "session start publishes the session id and the primary agent" {
  _setup_sandbox

  run _run_phase startup "{\"session_id\":\"abc-123\",\"cwd\":\"${SANDBOX_DIR}\"}"
  assert_success

  run cat "${PREAMBLE}"
  assert_success
  assert_output --partial "export DEV_BOT_SESSION_ID=abc-123"
  assert_output --partial "export DEV_BOT_AGENT_NAME=DevBot"
}

@test "a subagent tool call publishes its own agent name" {
  _setup_sandbox

  run _run_phase pre-tool \
    "{\"session_id\":\"abc-123\",\"agent_type\":\"Explore\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"},\"cwd\":\"${SANDBOX_DIR}\"}"
  assert_success

  run cat "${PREAMBLE}"
  assert_output --partial "export DEV_BOT_AGENT_NAME=Explore"
}

@test "the preamble is rewritten whole, never appended to" {
  _setup_sandbox

  _run_phase startup "{\"session_id\":\"one\",\"cwd\":\"${SANDBOX_DIR}\"}"
  _run_phase pre-tool \
    "{\"session_id\":\"one\",\"agent_type\":\"Plan\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"},\"cwd\":\"${SANDBOX_DIR}\"}"
  _run_phase stop "{\"session_id\":\"one\",\"cwd\":\"${SANDBOX_DIR}\"}"

  run bash -c "wc -l < '${PREAMBLE}' | tr -d ' '"
  assert_success
  assert_output "2"
}

@test "the last phase wins, so the name tracks the current caller" {
  _setup_sandbox

  _run_phase pre-tool \
    "{\"session_id\":\"one\",\"agent_type\":\"Explore\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"},\"cwd\":\"${SANDBOX_DIR}\"}"
  # The same session reporting no agent_type is the primary agent again.
  _run_phase pre-tool \
    "{\"session_id\":\"one\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"},\"cwd\":\"${SANDBOX_DIR}\"}"

  run cat "${PREAMBLE}"
  assert_output --partial "export DEV_BOT_AGENT_NAME=DevBot"
}

@test "a payload with no session id leaves the preamble untouched" {
  _setup_sandbox
  printf 'export PREEXISTING=1\n' > "${PREAMBLE}"

  run _run_phase startup "{\"cwd\":\"${SANDBOX_DIR}\"}"
  assert_success

  run cat "${PREAMBLE}"
  assert_output "export PREEXISTING=1"
}

@test "an unset CLAUDE_ENV_FILE is not an error" {
  _setup_sandbox
  unset CLAUDE_ENV_FILE

  run _run_phase startup "{\"session_id\":\"abc-123\",\"cwd\":\"${SANDBOX_DIR}\"}"
  assert_success
}

@test "an unwritable preamble path does not break the phase" {
  _setup_sandbox
  export CLAUDE_ENV_FILE="${SANDBOX_DIR}/no-such-dir/env-preamble.sh"

  run _run_phase startup "{\"session_id\":\"abc-123\",\"cwd\":\"${SANDBOX_DIR}\"}"
  assert_success
}
