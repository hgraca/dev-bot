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

# ── audit-25 F4: Chromium discovery must be platform-aware ────────────────────
# The wrapper's CHROME_REAL glob was Linux-only (chromium-*/chrome-linux*/chrome)
# so it never matched macOS's chrome-mac/Chromium.app layout, and with no
# Playwright Chromium installed chrome-devtools could not launch at all on a
# Mac. The discovery must branch on the OS and cover both layouts.

@test "audit-25: opencode template discovers chrome on macOS and Linux" {
  run grep -c 'chrome-mac/Chromium.app/Contents/MacOS/Chromium' \
    "${MODULE_DIR}/mcp.opencode.json"
  assert_equal "$output" "1"
  run grep -c 'chrome-linux\*/chrome' \
    "${MODULE_DIR}/mcp.opencode.json"
  assert_equal "$output" "1"
  run grep -c 'uname -s' "${MODULE_DIR}/mcp.opencode.json"
  assert_equal "$output" "1"
}

@test "audit-25: claudecode template discovers chrome on macOS and Linux" {
  run grep -c 'chrome-mac/Chromium.app/Contents/MacOS/Chromium' \
    "${MODULE_DIR}/mcp.claudecode.json"
  assert_equal "$output" "1"
  run grep -c 'chrome-linux\*/chrome' \
    "${MODULE_DIR}/mcp.claudecode.json"
  assert_equal "$output" "1"
  run grep -c 'uname -s' "${MODULE_DIR}/mcp.claudecode.json"
  assert_equal "$output" "1"
}

@test "audit-25: root opencode.dist.jsonc routes chrome-devtools through the wrapper with platform-aware discovery" {
  local dist="${MODULE_DIR}/../../..//opencode.dist.jsonc"
  # The root dist is what dist-initialized projects copy; its chrome-devtools
  # entry must carry the same wrapper + platform-aware discovery as the module
  # templates, otherwise registration skips the module version (key exists)
  # and the fix never reaches those projects.
  run grep -c 'chrome-devtools-mcp-wrapper\.js' "${dist}"
  assert_equal "$output" "1"
  run grep -c 'chrome-mac/Chromium.app/Contents/MacOS/Chromium' "${dist}"
  assert_equal "$output" "1"
  run grep -c 'chrome-linux\*/chrome' "${dist}"
  assert_equal "$output" "1"
}

# ── audit-25 F4: install/update must provision a sandboxable Chromium ────────
# The discovery glob only matches Playwright-downloaded Chromium; on machines
# without system Chrome that directory never exists, so chrome-devtools could
# not launch. install.sh and update.sh must run 'npx playwright install
# chromium' so a browser is actually present after setup.

@test "audit-25: install.sh exists, is executable, and runs playwright install chromium" {
  [[ -x "${MODULE_DIR}/install.sh" ]]
  run grep -q 'playwright install chromium' "${MODULE_DIR}/install.sh"
  assert_success
}

@test "audit-25: update.sh exists, is executable, and re-runs the install flow" {
  [[ -x "${MODULE_DIR}/update.sh" ]]
  run grep -q 'install\.sh' "${MODULE_DIR}/update.sh"
  assert_success
}

@test "audit-25: install.sh skips when a chromium binary is already present" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  mkdir -p "${tmpdir}/.cache/ms-playwright/chromium-9999/chrome-linux"
  touch "${tmpdir}/.cache/ms-playwright/chromium-9999/chrome-linux/chrome"
  chmod +x "${tmpdir}/.cache/ms-playwright/chromium-9999/chrome-linux/chrome"

  run env HOME="$tmpdir" bash "${MODULE_DIR}/install.sh"
  assert_success
  # Must skip the download — the discovery already found a chromium.
  assert_output --partial "already present"
  refute_output --partial "Installing Playwright Chromium"

  rm -rf "${tmpdir}"
}
