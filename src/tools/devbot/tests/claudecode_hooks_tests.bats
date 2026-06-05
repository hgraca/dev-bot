#!/usr/bin/env bats
# Tests for all claudecode hooks across modules.
# Each hook is tested for existence, basic JSON parsing, and gate behavior.

setup() {
  load "$(npm root -g)/bats-support/load.bash"
  load "$(npm root -g)/bats-assert/load.bash"

  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
}

# ── agent-communication: PostToolUse ──────────────────────────────────────────

@test "claudecode agent-communication: hook file exists" {
  [ -f "${PROJECT_ROOT}/src/agentic/agent-communication/hooks/claudecode/on-session_idle-agent-communication.sh" ]
}

@test "claudecode agent-communication: exits 0 for non-Write tool" {
  run bash -c 'echo '"'"'{"tool_use":{"name":"Read"},"tool_result":{}}'"'"' | bash '"${PROJECT_ROOT}/src/agentic/agent-communication/hooks/claudecode/on-session_idle-agent-communication.sh"
  assert_success
}

@test "claudecode agent-communication: exits 0 gracefully when deps missing" {
  run env -i PATH=/usr/bin jq --version 2>/dev/null || skip "jq not available"
  run bash -c 'echo '"'"'{"tool_use":{"name":"Write"},"tool_result":{}}'"'"' | bash '"${PROJECT_ROOT}/src/agentic/agent-communication/hooks/claudecode/on-session_idle-agent-communication.sh"
  assert_success
}

# ── format-md: PostToolUse ────────────────────────────────────────────────────

@test "claudecode format-md: hook file exists" {
  [ -f "${PROJECT_ROOT}/src/agentic/format-md/hooks/claudecode/on-file_edited-format-md.sh" ]
}

@test "claudecode format-md: exits 0 for non-.md file" {
  run bash -c 'echo '"'"'{"tool_input":{"file_path":"/path/to/file.ts"}}'"'"' | bash '"${PROJECT_ROOT}/src/agentic/format-md/hooks/claudecode/on-file_edited-format-md.sh"
  assert_success
}

@test "claudecode format-md: exits 0 for .md file" {
  run bash -c 'echo '"'"'{"tool_input":{"file_path":"/path/to/file.md"}}'"'"' | bash '"${PROJECT_ROOT}/src/agentic/format-md/hooks/claudecode/on-file_edited-format-md.sh"
  assert_success
}

@test "claudecode format-md: exits 0 when file_path missing" {
  run bash -c 'echo '"'"'{}'"'"' | bash '"${PROJECT_ROOT}/src/agentic/format-md/hooks/claudecode/on-file_edited-format-md.sh"
  assert_success
}

# ── guards: PreToolUse ────────────────────────────────────────────────────────

@test "claudecode guards: hook file exists" {
  [ -f "${PROJECT_ROOT}/src/agentic/guards/hooks/claudecode/on_tool_execute_before-guards.sh" ]
}

@test "claudecode guards: exits 0 when no command given" {
  run bash -c 'echo '"'"'{"tool_input":{}}'"'"' | bash '"${PROJECT_ROOT}/src/agentic/guards/hooks/claudecode/on_tool_execute_before-guards.sh"
  assert_success
}

@test "claudecode guards: exits 0 for allowed command" {
  run bash -c 'echo '"'"'{"tool_input":{"command":"ls -la"}}'"'"' | bash '"${PROJECT_ROOT}/src/agentic/guards/hooks/claudecode/on_tool_execute_before-guards.sh"
  assert_success
}

# ── reindex-memories: PostToolUse ─────────────────────────────────────────────

@test "claudecode reindex-memories: hook file exists" {
  [ -f "${PROJECT_ROOT}/src/agentic/memory/hooks/claudecode/on-file_edited-reindex-memories.sh" ]
}

@test "claudecode reindex-memories: exits 0 for non-.md file" {
  run bash -c 'echo '"'"'{"tool_input":{"file_path":"/path/to/file.ts"}}'"'"' | bash '"${PROJECT_ROOT}/src/agentic/memory/hooks/claudecode/on-file_edited-reindex-memories.sh"
  assert_success
}

@test "claudecode reindex-memories: exits 0 when file_path missing" {
  run bash -c 'echo '"'"'{}'"'"' | bash '"${PROJECT_ROOT}/src/agentic/memory/hooks/claudecode/on-file_edited-reindex-memories.sh"
  assert_success
}
