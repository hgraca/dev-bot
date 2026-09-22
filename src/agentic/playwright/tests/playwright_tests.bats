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

@test "mcp.json: docker path launches the pinned image, labelled for reaping" {
  run grep -qF 'docker run --rm -i --label dev-bot.mcp=playwright mcp/playwright' "${MODULE_DIR}/mcp.json"
  assert_success
  run grep -q 'docker info' "${MODULE_DIR}/mcp.json"
  assert_success
}

# ── down.sh: orphan reaping ───────────────────────────────────────────────────

# A docker stub that records every call and answers `ps -q` with the ids in the
# given file (empty file = no containers).
_stub_docker() {
  local bin_dir="$1" ids_file="$2"
  mkdir -p "${bin_dir}"
  cat > "${bin_dir}/docker" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${DOCKER_CALL_LOG}"
if [[ "\$1" == "ps" ]]; then cat "${ids_file}"; fi
exit 0
SH
  chmod +x "${bin_dir}/docker"
}

@test "down.sh: the label is the contract between launcher and reaper" {
  # A one-sided edit silently stops collecting orphans, and nothing else would
  # notice until the containers pile up again. down.sh reaches the value through
  # LABEL=, so assert on the value, not on a literal filter expression.
  local label="dev-bot.mcp=playwright"
  run grep -qF -- "--label ${label}" "${MODULE_DIR}/mcp.json"
  assert_success
  run grep -qF -- "${label}" "${MODULE_DIR}/down.sh"
  assert_success
}

@test "down.sh: removes every container carrying the dev-bot label" {
  local bin_dir tmpdir
  bin_dir="$(mktemp -d)"
  tmpdir="$(mktemp -d)"
  export DOCKER_CALL_LOG="${tmpdir}/docker.log"
  printf 'abc123\ndef456\n' > "${tmpdir}/ids"
  _stub_docker "${bin_dir}" "${tmpdir}/ids"
  export PATH="${bin_dir}:${PATH}"

  run bash "${MODULE_DIR}/down.sh"

  assert_success
  assert_output --partial "reaped 2 orphaned container(s)"
  run cat "${DOCKER_CALL_LOG}"
  assert_output --partial "ps -aq --filter label=dev-bot.mcp=playwright"
  assert_output --partial "rm -f abc123"
  assert_output --partial "rm -f def456"

  rm -rf "${bin_dir}" "${tmpdir}"
}

@test "down.sh: a container that will not die is warned about, not counted" {
  local bin_dir tmpdir
  bin_dir="$(mktemp -d)"
  tmpdir="$(mktemp -d)"
  export DOCKER_CALL_LOG="${tmpdir}/docker.log"
  printf 'abc123\ndef456\n' > "${tmpdir}/ids"
  mkdir -p "${bin_dir}"
  cat > "${bin_dir}/docker" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${DOCKER_CALL_LOG}"
if [[ "\$1" == "ps" ]]; then cat "${tmpdir}/ids"; exit 0; fi
if [[ "\$*" == "rm -f abc123" ]]; then exit 1; fi
exit 0
SH
  chmod +x "${bin_dir}/docker"
  export PATH="${bin_dir}:${PATH}"

  run bash "${MODULE_DIR}/down.sh"

  assert_success
  assert_output --partial "reaped 1 orphaned container(s)"
  assert_output --partial "could not remove container abc123"

  rm -rf "${bin_dir}" "${tmpdir}"
}

@test "down.sh: a clean no-op when nothing carries the label" {
  local bin_dir tmpdir
  bin_dir="$(mktemp -d)"
  tmpdir="$(mktemp -d)"
  export DOCKER_CALL_LOG="${tmpdir}/docker.log"
  : > "${tmpdir}/ids"
  _stub_docker "${bin_dir}" "${tmpdir}/ids"
  export PATH="${bin_dir}:${PATH}"

  run bash "${MODULE_DIR}/down.sh"

  assert_success
  assert_output --partial "no orphaned containers"
  refute grep -q "rm -f" "${DOCKER_CALL_LOG}"

  rm -rf "${bin_dir}" "${tmpdir}"
}

@test "mcp.json: ships the server disabled by default (enabled: false)" {
  # Wired in every harness but not started, so the ~3.5k tokens of tool schema
  # are costed only when the user turns it on. opencode honors the flag;
  # claudecode drops it — .mcp.json has no per-server on/off.
  run python3 -c "
import json
m = json.load(open('${MODULE_DIR}/mcp.json'))['mcp']['playwright']
assert m['enabled'] is False, m
print('DISABLED-BY-DEFAULT:OK')
"
  assert_success
  grep -qF 'DISABLED-BY-DEFAULT:OK' <<< "$output" || fail "playwright must ship enabled: false"
}
