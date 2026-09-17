#!/usr/bin/env bats
# =============================================================================
# src/harnesses/opencode/tests/reset_tests.bats
# Tests for opencode/reset.sh:
#   - harness disabled -> .opencode/ and opencode.jsonc left UNTOUCHED
#     (the user may use opencode independently of dev-bot)
#   - harness enabled  -> dev-bot symlinks removed, user files kept
#
# Runs the REAL reset.sh against a sandbox project dir whose
# .devbot.project.jsonc explicitly sets the opencode module state.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "${TEST_DIR}/../../../.." && pwd)"
  RESET_SCRIPT="${PROJECT_ROOT}/src/harnesses/opencode/reset.sh"

  SANDBOX_DIR="$(mktemp -d)"

  command -v python3 &>/dev/null || skip "python3 not installed"
  command -v jq &>/dev/null || skip "jq not installed"
  command -v bash &>/dev/null || skip "bash not installed"
}

teardown() {
  rm -rf "${SANDBOX_DIR}" 2>/dev/null || true
}

# _write_project_config <enabled|disabled>: write .devbot.project.jsonc with
# the opencode module explicitly set, overriding the global default.
_write_project_config() {
  local state="$1"
  local value=false
  [[ "${state}" == "enabled" ]] && value=true

  cat > "${SANDBOX_DIR}/.devbot.project.jsonc" <<JSONC_EOF
{
  "modules": {
    "opencode": ${value}
  }
}
JSONC_EOF
}

# _create_opencode_dir: realistic user .opencode/ with a user agent file and a
# dev-bot symlink (pointing into the real repo).
_create_opencode_dir() {
  mkdir -p "${SANDBOX_DIR}/.opencode/agents"
  echo "# User agent" > "${SANDBOX_DIR}/.opencode/agents/user-agent.md"
  ln -s "${PROJECT_ROOT}/src/agentic/devbot/agents" "${SANDBOX_DIR}/.opencode/agents/devbot"
  cat > "${SANDBOX_DIR}/opencode.jsonc" <<'JSONC_EOF'
{
  "mcp": {
    "devbot-tools": {"type": "local", "command": ["x"]},
    "qmd": {"type": "local", "command": ["qmd", "mcp"], "environment": {"QMD_LLAMA_GPU": true}}
  }
}
JSONC_EOF
}

# ── Disabled harness: leave everything untouched ───────────────────────────

@test "disabled: leaves .opencode/ and opencode.jsonc intact" {
  _write_project_config disabled
  _create_opencode_dir

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  assert [ -d "${SANDBOX_DIR}/.opencode" ]
  assert [ -f "${SANDBOX_DIR}/.opencode/agents/user-agent.md" ]
  assert [ -L "${SANDBOX_DIR}/.opencode/agents/devbot" ]
  assert [ -f "${SANDBOX_DIR}/opencode.jsonc" ]
}

@test "disabled: does not remove dev-bot symlinks either" {
  _write_project_config disabled
  _create_opencode_dir

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  assert [ -L "${SANDBOX_DIR}/.opencode/agents/devbot" ]
}

@test "disabled: skips gracefully when nothing exists" {
  _write_project_config disabled

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success
}

# ── Enabled harness: surgical cleanup only ─────────────────────────────────

@test "enabled: removes dev-bot symlinks but keeps user files and opencode.jsonc" {
  _write_project_config enabled
  _create_opencode_dir

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  # dev-bot symlink removed
  refute [ -L "${SANDBOX_DIR}/.opencode/agents/devbot" ]
  # user artifacts preserved
  assert [ -f "${SANDBOX_DIR}/.opencode/agents/user-agent.md" ]
  assert [ -f "${SANDBOX_DIR}/opencode.jsonc" ]
  assert [ -d "${SANDBOX_DIR}/.opencode" ]
}

@test "enabled: skips when no .opencode/ directory" {
  _write_project_config enabled

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success
}

# ── retired MCP key: reset must drop the qmd MCP entry ──────────────────────

@test "shared-gateway modules are on the stale-refresh list (manifest shape changed)" {
  # A module whose canonical mcp.json changes shape must be on REFRESH_MODULES,
  # or existing opencode.jsonc entries keep the old shape forever (registration
  # is skip-if-exists). All four converted modules moved from a per-instance
  # stdio process to a shared http gateway — every one of them must be listed,
  # since dropping any from the list leaves this test green without it.
  run grep -E '^[[:space:]]*REFRESH_MODULES=\(' "${RESET_SCRIPT}"
  assert_success
  for mod in codebase-memory mdctx signoz svelte; do
    [[ "$output" == *"$mod"* ]] || fail "$mod missing from REFRESH_MODULES: $output"
  done
}

@test "enabled: removes devbot-tools AND the retired qmd MCP key" {
  _write_project_config enabled
  _create_opencode_dir

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  # devbot-tools is on the stale-refresh list and init re-registers it; qmd's
  # MCP server was removed entirely, so its key is pruned as retired.
  run python3 -c "
import json, sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
d = load_jsonc('${SANDBOX_DIR}/opencode.jsonc')
mcp = d.get('mcp', {})
assert 'devbot-tools' not in mcp, mcp
assert 'qmd' not in mcp, mcp
print('MCP-CLEAN:OK')
"
  assert_success
  grep -qF 'MCP-CLEAN:OK' <<< "$output" || fail "MCP keys not removed"
}

# ── D7: prune plugin/MCP entries declared by now-DISABLED modules ────────────
# Registration is append-only, so a module that became disabled (e.g.
# codebase-index after a codebase_index_provider flip to codebase-memory) keeps
# its plugin/MCP entries in opencode.jsonc unless reset drops them. Fixture:
#   - codebase-index disabled via project modules override (module declares
#     plugin.opencode.json = ["opencode-codebase-index"])
#   - react globally disabled (canonical mcp.json declares "next-devtools")
#   - enabled modules' entries (on-hooks.ts plugin, chrome-devtools MCP) survive

_write_d7_fixture() {
  # opencode enabled; codebase-index (plugin) and react (mcp.json key
  # "next-devtools") disabled at project level. chrome-devtools is
  # force-ENABLED at project level too (its MCP entry must survive the prune):
  # the project modules map overrides the real global config, so the test is
  # hermetic — it must not depend on whatever per-machine .devbot.global.jsonc
  # disables (review F4).
  cat > "${SANDBOX_DIR}/.devbot.project.jsonc" <<JSONC_EOF
{
  "modules": {
    "opencode": true,
    "codebase-index": false,
    "react": false,
    "chrome-devtools": true
  }
}
JSONC_EOF

  mkdir -p "${SANDBOX_DIR}/.opencode/agents"
  # A user file keeps .opencode/ alive through reset's empty-directory cleanup;
  # without it the second reset exits early and the idempotency assertion below
  # compares against a file reset never touched.
  echo "# User agent" > "${SANDBOX_DIR}/.opencode/agents/user-agent.md"
  ln -s "${PROJECT_ROOT}/src/agentic/devbot/agents" "${SANDBOX_DIR}/.opencode/agents/devbot"
  # chrome-devtools entry must equal its canonical template translated to the
  # opencode shape, so reset's stale-refresh keeps it — a simplified literal
  # would read as stale (real template is the wrapper blob) and be pruned.
  python3 - "${PROJECT_ROOT}/src/_shared" "${PROJECT_ROOT}" "${SANDBOX_DIR}" <<'PY_EOF'
import json, sys
sys.path.insert(0, sys.argv[1])
from mcp_translate import load_canonical, server_map, translate
canon = load_canonical(sys.argv[2] + "/src/agentic/chrome-devtools/mcp.json")
entry = translate(server_map(canon)["chrome-devtools"], "opencode")
config = {
    "plugin": ["opencode-codebase-index", ".opencode/plugins/on-hooks.ts"],
    "mcp": {
        "next-devtools": {"type": "local", "command": ["next-devtools-mcp"]},
        "chrome-devtools": entry,
    },
}
with open(sys.argv[3] + "/opencode.jsonc", "w") as f:
    json.dump(config, f, indent=2)
    f.write("\n")
PY_EOF
}
@test "D7: reset removes plugin + MCP entries of disabled modules, keeps enabled ones" {
  _write_d7_fixture

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  run python3 -c "
import json, sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
d = load_jsonc('${SANDBOX_DIR}/opencode.jsonc')
plugins = d.get('plugin', [])
assert 'opencode-codebase-index' not in plugins, plugins
assert '.opencode/plugins/on-hooks.ts' in plugins, plugins
mcp = d.get('mcp', {})
assert 'next-devtools' not in mcp, mcp
assert 'chrome-devtools' in mcp, mcp
print('D7-PRUNE:OK')
"
  assert_success
  grep -qF 'D7-PRUNE:OK' <<< "$output" || fail "disabled-module entries not pruned"
}

@test "D7: second reset is byte-idempotent (no further changes)" {
  _write_d7_fixture

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  local after_first
  after_first="$(cat "${SANDBOX_DIR}/opencode.jsonc")"

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  refute_output --partial "nothing to reset"
  assert_equal "$(cat "${SANDBOX_DIR}/opencode.jsonc")" "${after_first}"
}

# ── playwright: stale npm-fallback entry must be refreshed ──────────────────
# e7e7cd40 repinned the canonical playwright manifest's npm fallback (bare
# `npx -y @playwright/mcp@0.0.79` -> an explicitly-resolved binary at the
# pinned version), so existing opencode.jsonc entries carry the old shape.
# playwright must be on REFRESH_MODULES: reset drops the stale entry so init
# re-registers the canonical one. Off the list, the old command survives
# forever (registration is skip-if-exists).

# The pre-e7e7cd40 canonical command, with {harness-dir} resolved to .opencode.
_PLAYWRIGHT_STALE_CMD='mkdir -p .agents/logs && if docker info >/dev/null 2>&1; then exec node .opencode/playwright-mcp-wrapper.js docker run --rm -i mcp/playwright 2>>.agents/logs/playwright-mcp.log; else exec node .opencode/playwright-mcp-wrapper.js npx -y @playwright/mcp@0.0.79 --browser chromium 2>>.agents/logs/playwright-mcp.log; fi'

# _write_playwright_fixture <stale|current>: playwright explicitly enabled at
# project level so the test is hermetic (the project modules map overrides the
# real global config). "current" generates the entry from the canonical
# manifest — a hand-written literal would read as stale and be pruned.
_write_playwright_fixture() {
  local mode="$1"

  cat > "${SANDBOX_DIR}/.devbot.project.jsonc" <<JSONC_EOF
{
  "modules": {
    "opencode": true,
    "playwright": true
  }
}
JSONC_EOF

  # Keep a user file so .opencode/ survives reset's empty-directory cleanup
  # (reset.sh: `find "${dir}" -type d -empty -delete`). An empty .opencode/ is
  # deleted by the first reset, and the second then exits at
  # `[[ ! -d "${OPENCODE_DIR}" ]]` before the refresh loop — which made the
  # byte-idempotency assertion below compare against a file the second reset
  # never touched.
  mkdir -p "${SANDBOX_DIR}/.opencode/agents"
  echo "# User agent" > "${SANDBOX_DIR}/.opencode/agents/user-agent.md"
  python3 - "${PROJECT_ROOT}/src/_shared" "${PROJECT_ROOT}" "${SANDBOX_DIR}" "${mode}" "${_PLAYWRIGHT_STALE_CMD}" <<'PY_EOF'
import json, sys
sys.path.insert(0, sys.argv[1])
from mcp_translate import load_canonical, server_map, translate

root, sandbox, mode, stale_cmd = sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
entry = translate(
    server_map(load_canonical(root + "/src/agentic/playwright/mcp.json"))["playwright"],
    "opencode",
)
if mode == "stale":
    entry = {"type": entry["type"], "command": ["bash", "-c", stale_cmd]}

with open(sandbox + "/opencode.jsonc", "w") as f:
    json.dump({"mcp": {"playwright": entry}}, f, indent=2)
    f.write("\n")
PY_EOF
}

@test "playwright: stale npm-fallback entry is dropped by reset (on the refresh list)" {
  _write_playwright_fixture stale

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  run python3 -c "
import sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
mcp = load_jsonc('${SANDBOX_DIR}/opencode.jsonc').get('mcp', {})
assert 'playwright' not in mcp, mcp
print('PLAYWRIGHT-REFRESHED:OK')
"
  assert_success
  grep -qF 'PLAYWRIGHT-REFRESHED:OK' <<< "$output" || fail "stale playwright entry not refreshed"
}

@test "playwright: current entry is kept and stays byte-idempotent" {
  _write_playwright_fixture current

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  run python3 -c "
import sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
mcp = load_jsonc('${SANDBOX_DIR}/opencode.jsonc').get('mcp', {})
assert 'playwright' in mcp, mcp
print('PLAYWRIGHT-KEPT:OK')
"
  assert_success
  grep -qF 'PLAYWRIGHT-KEPT:OK' <<< "$output" || fail "current playwright entry was churned"

  local after_first
  after_first="$(cat "${SANDBOX_DIR}/opencode.jsonc")"

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  # The comparison only means something if the second reset reached the refresh
  # loop: a missing .opencode/ makes reset exit early, and this assertion would
  # then pass while proving nothing.
  refute_output --partial "nothing to reset"
  assert_equal "$(cat "${SANDBOX_DIR}/opencode.jsonc")" "${after_first}"
}
