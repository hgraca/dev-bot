#!/usr/bin/env bats
# =============================================================================
# src/harnesses/claudecode/tests/on_hooks_env_tests.bats
# on-hooks.py publishes DEV_BOT_SESSION_ID and DEV_BOT_AGENT_NAME to the Bash
# preamble via $CLAUDE_ENV_FILE.
#
# Claude Code exports no session-id env var to the shell (upstream issue 47018),
# so the adapter writes the session id and the primary agent to the preamble
# file, which Claude Code runs before every Bash command — the claudecode
# counterpart of opencode's shell.env hook. The preamble is a session-start
# artefact: CLAUDE_ENV_FILE is documented as available only to SessionStart,
# Setup, CwdChanged and FileChanged hooks, so a subagent's own name is injected
# per command instead (see on_hooks_pre_tool_tests.bats).
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
  # A live Claude Code session exports this; its project could name another
  # agent, which would make the devbot assertion below environment-dependent.
  unset CLAUDE_PROJECT_DIR

  command -v python3 &>/dev/null || skip "python3 not installed"
}

teardown() {
  unset CLAUDE_PROJECT_DIR
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
  assert_output --partial "export DEV_BOT_AGENT_NAME=devbot"
}

@test "the primary agent is read from .claude/settings.json when present" {
  _setup_sandbox
  mkdir -p "${SANDBOX_DIR}/.claude"
  printf '{"agent":"teamlead"}\n' > "${SANDBOX_DIR}/.claude/settings.json"
  export CLAUDE_PROJECT_DIR="${SANDBOX_DIR}"

  run _run_phase startup "{\"session_id\":\"abc-123\",\"cwd\":\"${SANDBOX_DIR}\"}"
  assert_success

  run cat "${PREAMBLE}"
  assert_output --partial "export DEV_BOT_AGENT_NAME=teamlead"
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
  assert_output --partial "export DEV_BOT_AGENT_NAME=devbot"
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

@test "session start records the session id for tool calls" {
  _setup_sandbox
  export CLAUDE_PROJECT_DIR="${SANDBOX_DIR}"

  run _run_phase startup "{\"session_id\":\"abc-123\",\"cwd\":\"${SANDBOX_DIR}\"}"
  assert_success

  run cat "${SANDBOX_DIR}/.agents/logs/session-claudecode"
  assert_success
  assert_output "abc-123"
}

@test "every phase that names a session refreshes the marker" {
  _setup_sandbox
  export CLAUDE_PROJECT_DIR="${SANDBOX_DIR}"

  _run_phase startup "{\"session_id\":\"one\",\"cwd\":\"${SANDBOX_DIR}\"}"
  _run_phase pre-tool \
    "{\"session_id\":\"two\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"},\"cwd\":\"${SANDBOX_DIR}\"}"

  run cat "${SANDBOX_DIR}/.agents/logs/session-claudecode"
  assert_output "two"
}

@test "a payload with no session id writes no marker" {
  _setup_sandbox
  export CLAUDE_PROJECT_DIR="${SANDBOX_DIR}"

  run _run_phase startup "{\"cwd\":\"${SANDBOX_DIR}\"}"
  assert_success

  run test -e "${SANDBOX_DIR}/.agents/logs/session-claudecode"
  assert_failure
}

@test "a session-usage call is bound to the calling session" {
  _setup_sandbox

  run _run_phase session-arg \
    "{\"session_id\":\"abc-123\",\"tool_name\":\"mcp__devbot-tools__session-usage\",\"tool_input\":{\"args\":[]},\"cwd\":\"${SANDBOX_DIR}\"}"
  assert_success

  echo "$output" | python3 -c '
import json, sys
updated = json.load(sys.stdin)["hookSpecificOutput"]["updatedInput"]
assert updated["args"] == ["--session", "abc-123"], updated
'
}

@test "a caller-supplied --session is replaced by the hook" {
  _setup_sandbox

  run _run_phase session-arg \
    "{\"session_id\":\"abc-123\",\"tool_name\":\"mcp__devbot-tools__session-usage\",\"tool_input\":{\"args\":[\"--json\",\"--session\",\"other\"]},\"cwd\":\"${SANDBOX_DIR}\"}"
  assert_success

  echo "$output" | python3 -c '
import json, sys
updated = json.load(sys.stdin)["hookSpecificOutput"]["updatedInput"]
assert updated["args"] == ["--json", "--session", "abc-123"], updated
'
}

@test "another MCP tool is left untouched" {
  _setup_sandbox

  run _run_phase session-arg \
    "{\"session_id\":\"abc-123\",\"tool_name\":\"mcp__devbot-tools__git-report\",\"tool_input\":{\"args\":[]},\"cwd\":\"${SANDBOX_DIR}\"}"
  assert_success
  assert_output ""
}

@test "an escaping devbot_dir falls back to .agents" {
  _setup_sandbox
  export CLAUDE_PROJECT_DIR="${SANDBOX_DIR}"
  printf '{"devbot_dir":"../outside"}\n' > "${SANDBOX_DIR}/.devbot.project.jsonc"

  run _run_phase startup "{\"session_id\":\"abc-123\",\"cwd\":\"${SANDBOX_DIR}\"}"
  assert_success

  run cat "${SANDBOX_DIR}/.agents/logs/session-claudecode"
  assert_output "abc-123"
}
