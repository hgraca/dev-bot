#!/usr/bin/env bats
# =============================================================================
# src/agentic/chrome-devtools/tests/chrome-devtools_tests.bats
# Tests for the chrome-devtools module's init.sh symlink wiring and mcp.json
# launch routing.
#
# The chrome-devtools MCP server (npx chrome-devtools-mcp) crashed with an
# unhandled EPIPE at session teardown (audit-19 FAIL). The shared wrapper
# (src/_shared/mcp-stdio-wrapper.js) swallows it; this verifies init.sh wires
# it under the module-specific name and the mcp.json commands route through it.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  INIT_TOOL="$MODULE_DIR/init.sh"
  SHARED_WRAPPER="$(cd "$MODULE_DIR/../../.." && pwd)/src/_shared/mcp-stdio-wrapper.js"
}

# ── init.sh wiring ────────────────────────────────────────────────────────────

setup_project() {
  printf '{\n  "modules": { "claudecode": true, "opencode": true }\n}\n' \
    > "${1}/.devbot.project.jsonc"
}

@test "init.sh: symlinks the shared wrapper into .claude and .opencode" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  setup_project "${tmpdir}"

  run bash "${INIT_TOOL}" "${tmpdir}"

  assert_success
  [[ -L "${tmpdir}/.claude/chrome-devtools-mcp-wrapper.js" ]]
  [[ -L "${tmpdir}/.opencode/chrome-devtools-mcp-wrapper.js" ]]
  run readlink -f "${tmpdir}/.claude/chrome-devtools-mcp-wrapper.js"
  assert_output "${SHARED_WRAPPER}"

  rm -rf "${tmpdir}"
}

# ── mcp.json launch routing ───────────────────────────────────────────────────

@test "mcp.json: both harness launch commands route through the wrapper" {
  run grep -c 'node \.claude/chrome-devtools-mcp-wrapper\.js npx' \
    "${MODULE_DIR}/mcp.claudecode.json"
  assert_equal "$output" "1"
  run grep -c 'node \.opencode/chrome-devtools-mcp-wrapper\.js npx' \
    "${MODULE_DIR}/mcp.opencode.json"
  assert_equal "$output" "1"
}
