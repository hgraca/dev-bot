#!/usr/bin/env bats
# =============================================================================
# src/agentic/playwright/tests/playwright_tests.bats
# Tests for the playwright module's init.sh symlink wiring.
#
# The wrapper itself (EPIPE swallow) lives in src/_shared/mcp-stdio-wrapper.js
# and is behavior-tested in src/_shared/tests/mcp-stdio-wrapper_tests.bats.
# This file only verifies that init.sh wires the shared wrapper into the
# project harness dirs under the module-specific name.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  INIT_TOOL="$MODULE_DIR/init.sh"
  # The shared wrapper this module's init.sh must symlink to.
  SHARED_WRAPPER="$(cd "$MODULE_DIR/../../.." && pwd)/src/_shared/mcp-stdio-wrapper.js"
}

# ── init.sh wiring ────────────────────────────────────────────────────────────

# The global devbot config disables claudecode by default (dev-bot runs on
# opencode), so a bare tmpdir would skip the .claude symlink. Give the fixture
# a project config enabling both harnesses — project overrides global.

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
  [[ -L "${tmpdir}/.claude/playwright-mcp-wrapper.js" ]]
  [[ -L "${tmpdir}/.opencode/playwright-mcp-wrapper.js" ]]
  # The symlinks resolve to the shared wrapper, not a dangling local copy.
  run readlink -f "${tmpdir}/.claude/playwright-mcp-wrapper.js"
  assert_output "${SHARED_WRAPPER}"

  rm -rf "${tmpdir}"
}

@test "init.sh: idempotent — re-run leaves the symlinks intact" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  setup_project "${tmpdir}"

  run bash "${INIT_TOOL}" "${tmpdir}"
  assert_success
  run bash "${INIT_TOOL}" "${tmpdir}"
  assert_success

  [[ -L "${tmpdir}/.claude/playwright-mcp-wrapper.js" ]]
  [[ -L "${tmpdir}/.opencode/playwright-mcp-wrapper.js" ]]

  rm -rf "${tmpdir}"
}
