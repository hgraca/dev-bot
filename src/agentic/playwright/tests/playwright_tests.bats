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

# T1.2: init.sh self-heals via install.sh, which would otherwise run a REAL
# global `npm install -g` during tests. Isolate the install path: stub npm,
# provide a fake binary at the pinned version.
_stub_npm_kit() {
  local pin
  pin="$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' "${MODULE_DIR}/versions.env" | head -1)"
  mkdir -p "${1}/.npm-global/bin" "${1}/stubbin"
  printf '#!/bin/bash\necho "%s"\n' "${pin}" > "${1}/.npm-global/bin/playwright-mcp"
  chmod +x "${1}/.npm-global/bin/playwright-mcp"
  printf '#!/bin/bash\nif [ "$1 $2 $3" = "config get prefix" ]; then echo "/nonexistent"; exit 0; fi\nexit 0\n' \
    > "${1}/stubbin/npm"
  chmod +x "${1}/stubbin/npm"
}

@test "init.sh: symlinks the shared wrapper into .claude and .opencode" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  setup_project "${tmpdir}"
  _stub_npm_kit "${tmpdir}"

  run env HOME="${tmpdir}" PATH="${tmpdir}/stubbin:${PATH}" bash "${INIT_TOOL}" "${tmpdir}"

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
  _stub_npm_kit "${tmpdir}"

  run env HOME="${tmpdir}" PATH="${tmpdir}/stubbin:${PATH}" bash "${INIT_TOOL}" "${tmpdir}"
  assert_success
  run env HOME="${tmpdir}" PATH="${tmpdir}/stubbin:${PATH}" bash "${INIT_TOOL}" "${tmpdir}"
  assert_success

  [[ -L "${tmpdir}/.claude/playwright-mcp-wrapper.js" ]]
  [[ -L "${tmpdir}/.opencode/playwright-mcp-wrapper.js" ]]

  rm -rf "${tmpdir}"
}

# ── T1.2: version pinning ─────────────────────────────────────────────────────

@test "versions.env: exists and pins a semver @playwright/mcp version" {
  [[ -f "${MODULE_DIR}/versions.env" ]]
  run bash -c "source '${MODULE_DIR}/versions.env' && [[ -n \"\${PLAYWRIGHT_MCP_VERSION:-}\" ]]"
  assert_success
  run grep -cE '^PLAYWRIGHT_MCP_VERSION=[0-9]+\.[0-9]+\.[0-9]+$' "${MODULE_DIR}/versions.env"
  assert_equal "$output" "1"
}

@test "install.sh: exists, is executable, and installs the pinned package" {
  [[ -x "${MODULE_DIR}/install.sh" ]]
  run grep -q 'versions\.env' "${MODULE_DIR}/install.sh"
  assert_success
  run grep -qF 'npm install -g "@playwright/mcp@${PLAYWRIGHT_MCP_VERSION}"' "${MODULE_DIR}/install.sh"
  assert_success
}

@test "update.sh: exists, is executable, resolves npm latest, and bumps versions.env" {
  # User policy: the installed version is bumped to npm latest ONLY on
  # 'devbot update', and the rewritten pin keeps every consumer at the new
  # version on their next install.
  [[ -x "${MODULE_DIR}/update.sh" ]]
  run grep -q 'npm view "@playwright/mcp" version' "${MODULE_DIR}/update.sh"
  assert_success
  run grep -qF 'npm install -g "@playwright/mcp@${LATEST}"' "${MODULE_DIR}/update.sh"
  assert_success
  run grep -q 'versions\.env' "${MODULE_DIR}/update.sh"
  assert_success
}

# ── T1.2: mcp.json launch routing ────────────────────────────────────────────

@test "mcp.json: npm fallback is explicit-prefix resolved, never npx/@latest" {
  # No runtime version resolution: no npx, no @latest — the fallback binary is
  # installed at the pin and resolved by explicit prefix (never via PATH).
  refute grep -q 'npx' "${MODULE_DIR}/mcp.json"
  refute grep -q '@latest' "${MODULE_DIR}/mcp.json"
  run grep -q 'config get prefix' "${MODULE_DIR}/mcp.json"
  assert_success
}

@test "mcp.json: fallback fails loudly when the binary is not installed" {
  run grep -q 'devbot install' "${MODULE_DIR}/mcp.json"
  assert_success
}

@test "mcp.json: docker path unchanged" {
  run grep -q 'docker run --rm -i mcp/playwright' "${MODULE_DIR}/mcp.json"
  assert_success
  run grep -q 'docker info' "${MODULE_DIR}/mcp.json"
  assert_success
}
