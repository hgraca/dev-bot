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

# T1.2: init.sh self-heals via install.sh, which would otherwise run a REAL
# global `npm install -g` during tests. Isolate the install path: stub npm,
# provide a fake binary at the pinned version, and a present chromium.
_stub_runtime_kit() {
  local pin
  pin="$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' "${MODULE_DIR}/versions.env" | head -1)"
  mkdir -p "${1}/.cache/ms-playwright/chromium-9999/chrome-linux" \
    "${1}/.npm-global/bin" "${1}/stubbin"
  touch "${1}/.cache/ms-playwright/chromium-9999/chrome-linux/chrome"
  chmod +x "${1}/.cache/ms-playwright/chromium-9999/chrome-linux/chrome"
  printf '#!/bin/bash\necho "%s"\n' "${pin}" > "${1}/.npm-global/bin/chrome-devtools-mcp"
  chmod +x "${1}/.npm-global/bin/chrome-devtools-mcp"
  printf '#!/bin/bash\nif [ "$1 $2 $3" = "config get prefix" ]; then echo "/nonexistent"; exit 0; fi\nexit 0\n' \
    > "${1}/stubbin/npm"
  chmod +x "${1}/stubbin/npm"
}

@test "init.sh: symlinks the shared wrapper into .claude and .opencode" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  setup_project "${tmpdir}"
  _stub_runtime_kit "${tmpdir}"

  run env HOME="${tmpdir}" PATH="${tmpdir}/stubbin:${PATH}" bash "${INIT_TOOL}" "${tmpdir}"

  assert_success
  [[ -L "${tmpdir}/.claude/chrome-devtools-mcp-wrapper.js" ]]
  [[ -L "${tmpdir}/.opencode/chrome-devtools-mcp-wrapper.js" ]]
  run readlink -f "${tmpdir}/.claude/chrome-devtools-mcp-wrapper.js"
  assert_output "${SHARED_WRAPPER}"

  rm -rf "${tmpdir}"
}

@test "init.sh: symlinks the serve launcher into .claude and .opencode" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  setup_project "${tmpdir}"
  _stub_runtime_kit "${tmpdir}"

  run env HOME="${tmpdir}" PATH="${tmpdir}/stubbin:${PATH}" bash "${INIT_TOOL}" "${tmpdir}"

  assert_success
  [[ -L "${tmpdir}/.claude/chrome-devtools-serve.mcp.sh" ]]
  [[ -L "${tmpdir}/.opencode/chrome-devtools-serve.mcp.sh" ]]

  rm -rf "${tmpdir}"
}

@test "serve.mcp.sh: parses cleanly (bash -n) and is executable" {
  [[ -x "${MODULE_DIR}/serve.mcp.sh" ]]
  run bash -n "${MODULE_DIR}/serve.mcp.sh"
  assert_success
}

# ── mcp.json launch routing ───────────────────────────────────────────────────

@test "mcp.json: canonical manifest routes both harnesses through the serve launcher" {
  # The single canonical mcp.json carries a {harness-dir} token; the shared
  # translator resolves it to the per-harness launcher path (.opencode/.claude).
  PROJECT_ROOT="$(cd "$MODULE_DIR/../../.." && pwd)"
  run python3 "$PROJECT_ROOT/src/_shared/mcp_translate.py" "$MODULE_DIR/mcp.json" opencode
  assert_success
  assert_output --partial '.opencode/chrome-devtools-serve.mcp.sh'
  run python3 "$PROJECT_ROOT/src/_shared/mcp_translate.py" "$MODULE_DIR/mcp.json" claudecode
  assert_success
  assert_output --partial '.claude/chrome-devtools-serve.mcp.sh'
}

@test "mcp.json: launch command never uses npx or @latest runtime resolution" {
  # T1.2: the runtime must launch the globally installed, pinned binary — never
  # re-resolve 'latest' at session start (nondeterministic version, npx download
  # churn, extra npm-exec/sh -c processes).
  refute grep -q 'npx' "${MODULE_DIR}/mcp.json"
  refute grep -q '@latest' "${MODULE_DIR}/mcp.json"
  refute grep -q 'npm exec' "${MODULE_DIR}/mcp.json"
}

# ── T1.2: version pinning ─────────────────────────────────────────────────────

@test "versions.env: exists and pins a semver chrome-devtools-mcp version" {
  [[ -f "${MODULE_DIR}/versions.env" ]]
  run bash -c "source '${MODULE_DIR}/versions.env' && [[ -n \"\${CHROME_DEVTOOLS_MCP_VERSION:-}\" ]]"
  assert_success
  run grep -cE '^CHROME_DEVTOOLS_MCP_VERSION=[0-9]+\.[0-9]+\.[0-9]+$' "${MODULE_DIR}/versions.env"
  assert_equal "$output" "1"
}

@test "install.sh: installs the globally pinned package from versions.env" {
  run grep -qF 'npm install -g "chrome-devtools-mcp@${CHROME_DEVTOOLS_MCP_VERSION}"' "${MODULE_DIR}/install.sh"
  assert_success
  run grep -q 'versions\.env' "${MODULE_DIR}/install.sh"
  assert_success
}

@test "update.sh: resolves npm latest, installs it, and bumps versions.env" {
  # User policy: the installed version is bumped to npm latest ONLY on
  # 'devbot update', and the rewritten pin keeps every consumer at the new
  # version on their next install.
  run grep -q 'npm view chrome-devtools-mcp version' "${MODULE_DIR}/update.sh"
  assert_success
  run grep -qF 'npm install -g "chrome-devtools-mcp@${LATEST}"' "${MODULE_DIR}/update.sh"
  assert_success
  run grep -q 'versions\.env' "${MODULE_DIR}/update.sh"
  assert_success
}

# ── serve launcher ────────────────────────────────────────────────────────────

@test "serve.mcp.sh: resolves the binary by explicit prefix, never via PATH" {
  # Trap: /usr/bin/chrome-devtools-mcp (a stale 0.17.0 root-owned binary, and
  # not the npm package) could be picked up by a bare-name lookup. Resolution
  # must try explicit install prefixes and must never fall back to PATH
  # resolution, so the stale system binary can never run.
  [[ -f "${MODULE_DIR}/serve.mcp.sh" ]]
  run grep -q 'config get prefix' "${MODULE_DIR}/serve.mcp.sh"
  assert_success
  run grep -q '\.npm-global/bin/' "${MODULE_DIR}/serve.mcp.sh"
  assert_success
  refute grep -q 'command -v chrome-devtools-mcp' "${MODULE_DIR}/serve.mcp.sh"
}

@test "serve.mcp.sh: fails loudly when the pinned binary is not installed" {
  run grep -q 'devbot install' "${MODULE_DIR}/serve.mcp.sh"
  assert_success
}

@test "serve.mcp.sh: warns when installed version drifts from the pin" {
  run grep -q 'WARN' "${MODULE_DIR}/serve.mcp.sh"
  assert_success
  run grep -q 'CHROME_DEVTOOLS_MCP_VERSION' "${MODULE_DIR}/serve.mcp.sh"
  assert_success
}

@test "serve.mcp.sh: execs the server through the shared EPIPE wrapper via node" {
  # The shared wrapper preloads the EPIPE guard only for node/npx children;
  # exec through 'node <resolved .js>' (never the bare bin name) so the guard
  # applies and session-teardown EPIPEs stay swallowed (audit-19).
  run grep -q 'node "' "${MODULE_DIR}/serve.mcp.sh"
  assert_success
  run grep -q 'chrome-devtools-mcp-wrapper\.js' "${MODULE_DIR}/serve.mcp.sh"
  assert_success
}

# ── audit-25 F4: Chromium discovery must be platform-aware ────────────────────
# The wrapper's CHROME_REAL glob was Linux-only (chromium-*/chrome-linux*/chrome)
# so it never matched macOS's chrome-mac/Chromium.app layout, and with no
# Playwright Chromium installed chrome-devtools could not launch at all on a
# Mac. The discovery must branch on the OS and cover both layouts.

@test "audit-25: serve launcher discovers chrome on macOS and Linux" {
  # The Chromium discovery lives in serve.mcp.sh since T1.2 (mcp.json now just
  # execs the launcher).
  run grep -c 'chrome-mac/Chromium.app/Contents/MacOS/Chromium' \
    "${MODULE_DIR}/serve.mcp.sh"
  assert_equal "$output" "1"
  run grep -c 'chrome-linux\*/chrome' \
    "${MODULE_DIR}/serve.mcp.sh"
  assert_equal "$output" "1"
  run grep -c 'uname -s' "${MODULE_DIR}/serve.mcp.sh"
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
  _stub_runtime_kit "${tmpdir}"

  run env HOME="$tmpdir" PATH="${tmpdir}/stubbin:$PATH" bash "${MODULE_DIR}/install.sh"
  assert_success
  # Must skip the download — the discovery already found a chromium.
  assert_output --partial "already present"
  refute_output --partial "Installing Playwright Chromium"

  rm -rf "${tmpdir}"
}
