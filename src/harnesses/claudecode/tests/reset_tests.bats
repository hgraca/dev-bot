#!/usr/bin/env bats
# =============================================================================
# src/harnesses/claudecode/tests/reset_tests.bats
# Tests for claudecode/reset.sh:
#   - harness disabled -> .claude/, CLAUDE.md, .mcp.json left UNTOUCHED
#     (the user may use Claude Code independently of dev-bot)
#   - harness enabled  -> dev-bot symlinks removed, user files kept
#
# Runs the REAL reset.sh against a sandbox project dir whose
# .devbot.project.jsonc explicitly sets the claudecode module state.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "${TEST_DIR}/../../../.." && pwd)"
  RESET_SCRIPT="${PROJECT_ROOT}/src/harnesses/claudecode/reset.sh"

  SANDBOX_DIR="$(mktemp -d)"

  command -v python3 &>/dev/null || skip "python3 not installed"
  command -v jq &>/dev/null || skip "jq not installed"
  command -v bash &>/dev/null || skip "bash not installed"
}

teardown() {
  rm -rf "${SANDBOX_DIR}" 2>/dev/null || true
}

# _write_project_config <enabled|disabled>: write .devbot.project.jsonc with
# the claudecode module explicitly set, overriding the global default.
_write_project_config() {
  local state="$1"
  local value=false
  [[ "${state}" == "enabled" ]] && value=true

  cat > "${SANDBOX_DIR}/.devbot.project.jsonc" <<JSONC_EOF
{
  "modules": {
    "claudecode": ${value}
  }
}
JSONC_EOF
}

# _create_claude_dir: realistic user .claude/ with a user agent file and a
# dev-bot symlink (pointing into the real repo).
_create_claude_dir() {
  mkdir -p "${SANDBOX_DIR}/.claude/agents"
  echo "# User agent" > "${SANDBOX_DIR}/.claude/agents/user-agent.md"
  ln -s "${PROJECT_ROOT}/src/agentic/devbot/agents" "${SANDBOX_DIR}/.claude/agents/devbot"
  echo '{"mcpServers": {"devbot-tools": {"type": "stdio", "command": "x"}}}' > "${SANDBOX_DIR}/.mcp.json"
  echo "# Project instructions" > "${SANDBOX_DIR}/CLAUDE.md"
}

# ── Disabled harness: leave everything untouched ───────────────────────────

@test "disabled: leaves .claude/, CLAUDE.md and .mcp.json intact" {
  _write_project_config disabled
  _create_claude_dir

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  assert [ -d "${SANDBOX_DIR}/.claude" ]
  assert [ -f "${SANDBOX_DIR}/.claude/agents/user-agent.md" ]
  assert [ -L "${SANDBOX_DIR}/.claude/agents/devbot" ]
  assert [ -f "${SANDBOX_DIR}/.mcp.json" ]
  assert [ -f "${SANDBOX_DIR}/CLAUDE.md" ]
}

@test "disabled: does not remove dev-bot symlinks either" {
  _write_project_config disabled
  _create_claude_dir

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  assert [ -L "${SANDBOX_DIR}/.claude/agents/devbot" ]
}

@test "disabled: skips gracefully when nothing exists" {
  _write_project_config disabled

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success
}

# ── Enabled harness: surgical cleanup only ─────────────────────────────────

@test "enabled: removes dev-bot symlinks but keeps user files and CLAUDE.md" {
  _write_project_config enabled
  _create_claude_dir

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  # dev-bot symlink removed
  refute [ -L "${SANDBOX_DIR}/.claude/agents/devbot" ]
  # user artifacts preserved
  assert [ -f "${SANDBOX_DIR}/.claude/agents/user-agent.md" ]
  assert [ -f "${SANDBOX_DIR}/.mcp.json" ]
  assert [ -f "${SANDBOX_DIR}/CLAUDE.md" ]
  assert [ -d "${SANDBOX_DIR}/.claude" ]
}

@test "enabled: skips when no .claude/ directory" {
  _write_project_config enabled

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success
}

# ── Hook/symlink ordering (audit-31 §2 torn window) ─────────────────────────

@test "enabled: clears settings.local.json hooks and removes the plugin symlinks they reference" {
  _write_project_config enabled
  mkdir -p "${SANDBOX_DIR}/.claude/plugins"
  # A realistic settings.local.json registering the PreToolUse dispatcher...
  cat > "${SANDBOX_DIR}/.claude/settings.local.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "python3 .claude/plugins/on-hooks.py pre-tool" }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "python3 .claude/plugins/on-hooks.py startup" }
        ]
      }
    ]
  }
}
JSON
  # ...and the dispatcher symlink it invokes (pointing into the real repo).
  ln -s "${PROJECT_ROOT}/src/harnesses/claudecode/hooks/on-hooks.py" \
    "${SANDBOX_DIR}/.claude/plugins/on-hooks.py"

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  # End state is consistent: no hook entry references a removed script.
  run python3 -c "
import json
with open('${SANDBOX_DIR}/.claude/settings.local.json') as f:
    data = json.load(f)
assert 'hooks' not in data, 'hooks key must be cleared'
print('hooks cleared')
"
  assert_success
  assert_output "hooks cleared"
  refute [ -L "${SANDBOX_DIR}/.claude/plugins/on-hooks.py" ]
}

@test "reset.sh clears settings.local.json hooks BEFORE removing plugin symlinks (no torn window)" {
  # audit-31 §2: removing .claude/plugins/on-hooks.py while settings.local.json
  # still registers it makes a concurrent PreToolUse hit a missing script →
  # Claude Code treats the hook error as "no decision" → default-allow. The
  # hook entries must be cleared first, so no registered hook ever references
  # a script that is about to be deleted.
  hook_clear_line="$(grep -n "Clear dev-bot hooks from .claude/settings.local.json" \
    "${RESET_SCRIPT}" | head -1 | cut -d: -f1)"
  symlink_loop_line="$(grep -n "for subdir in agents commands skills plugins tools" \
    "${RESET_SCRIPT}" | head -1 | cut -d: -f1)"

  [[ -n "${hook_clear_line}" ]] || fail "hook-clearing block not found in reset.sh"
  [[ -n "${symlink_loop_line}" ]] || fail "symlink-removal loop not found in reset.sh"
  (( hook_clear_line < symlink_loop_line )) \
    || fail "hook clear (line ${hook_clear_line}) must precede symlink removal (line ${symlink_loop_line})"
}
