#!/usr/bin/env bats
# =============================================================================
# src/harnesses/claudecode/tests/on_hooks_pre_tool_tests.bats
# Functional tests for on-hooks.py's pre-tool phase fail-closed contract.
#
# Guards audit-31 FAIL §2: when a `blocking: true` command.before hook's
# subprocess fails to execute (missing interpreter/script, non-zero exit,
# unparseable output), the guarded command must be DENIED — Claude Code treats
# a hook execution error as "no decision" → default-allow, so the adapter must
# emit an explicit deny instead of silently letting the command through.
#
# Sandbox pattern (mirrors skills_flat_tests.bats): on-hooks.py computes
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
# DEV_BOT_ROOT resolve to the sandbox, then create a fake module manifest.
_setup_sandbox() {
  mkdir -p "${SANDBOX_DIR}/src/harnesses/claudecode/hooks"
  cp "${PROJECT_ROOT}/src/harnesses/claudecode/hooks/on-hooks.py" \
    "${SANDBOX_DIR}/src/harnesses/claudecode/hooks/on-hooks.py"

  # Fake blocking guard module: a command.before hook on Bash with a guard
  # script whose behavior each test controls.
  mkdir -p "${SANDBOX_DIR}/src/agentic/fakeguard"
}

# _write_guard <script-body>: write the fake guard module's hook script.
_write_guard() {
  local body="$1"
  printf '%s\n' '#!/usr/bin/env bash' "${body}" \
    > "${SANDBOX_DIR}/src/agentic/fakeguard/guard.sh"
  chmod +x "${SANDBOX_DIR}/src/agentic/fakeguard/guard.sh"

  cat > "${SANDBOX_DIR}/src/agentic/fakeguard/hooks.json" <<'JSON'
{
  "hooks": [
    {
      "id": "fakeguard",
      "event": "command.before",
      "match": { "tool": ["bash", "shell"] },
      "run": ["bash", "{module}/guard.sh", "--command", "{command}"],
      "blocking": true
    }
  ]
}
JSON
}

# _run_pre_tool <command>: feed a PreToolUse JSON event to on-hooks.py.
_run_pre_tool() {
  local command="$1"
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}\n' \
    "${command}" "${SANDBOX_DIR}" \
    | python3 "${SANDBOX_DIR}/src/harnesses/claudecode/hooks/on-hooks.py" pre-tool
}

@test "blocking guard that exits non-zero denies the command (fail closed)" {
  _setup_sandbox
  # Guard crashes (e.g. interpreter missing at runtime) — exits 3, no JSON.
  _write_guard 'exit 3'

  run _run_pre_tool "rm -rf /tmp/x"
  assert_success
  # The deny decision must be on stdout for Claude Code's PreToolUse contract.
  assert_output --partial '"permissionDecision": "deny"'
  assert_output --partial 'guard temporarily unavailable'
}

@test "blocking guard whose script is missing denies the command (fail closed)" {
  _setup_sandbox
  # Manifest references a script that does not exist — subprocess fails to
  # execute (bash returns 127).
  cat > "${SANDBOX_DIR}/src/agentic/fakeguard/hooks.json" <<'JSON'
{
  "hooks": [
    {
      "id": "fakeguard",
      "event": "command.before",
      "match": { "tool": ["bash", "shell"] },
      "run": ["bash", "{module}/does-not-exist.sh", "--command", "{command}"],
      "blocking": true
    }
  ]
}
JSON

  run _run_pre_tool "rm -rf /tmp/x"
  assert_success
  assert_output --partial '"permissionDecision": "deny"'
}

@test "blocking guard with unparseable output denies the command (fail closed)" {
  _setup_sandbox
  # Guard prints garbage instead of the {"blocked": bool} contract.
  _write_guard 'echo "not json at all"'

  run _run_pre_tool "rm -rf /tmp/x"
  assert_success
  assert_output --partial '"permissionDecision": "deny"'
}

@test "blocking guard that allows the command emits no deny decision" {
  _setup_sandbox
  _write_guard 'echo "{\"blocked\": false}"'

  run _run_pre_tool "ls /tmp"
  assert_success
  refute_output --partial '"permissionDecision": "deny"'
}

@test "blocking guard that blocks the command emits the deny decision with reason" {
  _setup_sandbox
  _write_guard 'echo "{\"blocked\": true, \"message\": \"rm -rf is blocked\"}"'

  run _run_pre_tool "rm -rf /tmp/x"
  assert_success
  assert_output --partial '"permissionDecision": "deny"'
  assert_output --partial 'rm -rf is blocked'
}

@test "non-blocking hook that fails does not emit a deny decision" {
  _setup_sandbox
  # Same shape but without "blocking": true — a failing non-blocking hook must
  # not deny the command (only blocking hooks fail closed).
  mkdir -p "${SANDBOX_DIR}/src/agentic/fakenonblocking"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 3' \
    > "${SANDBOX_DIR}/src/agentic/fakenonblocking/guard.sh"
  chmod +x "${SANDBOX_DIR}/src/agentic/fakenonblocking/guard.sh"
  cat > "${SANDBOX_DIR}/src/agentic/fakenonblocking/hooks.json" <<'JSON'
{
  "hooks": [
    {
      "id": "fakenonblocking",
      "event": "command.before",
      "match": { "tool": ["bash", "shell"] },
      "run": ["bash", "{module}/guard.sh", "--command", "{command}"]
    }
  ]
}
JSON

  run _run_pre_tool "ls /tmp"
  assert_success
  refute_output --partial '"permissionDecision": "deny"'
}
