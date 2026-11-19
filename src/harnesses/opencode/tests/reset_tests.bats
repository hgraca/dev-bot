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

# _write_project_config <enabled|disabled>: write .devbot.project.jsonc
# selecting this harness (enabled) or the other one (disabled). The root
# `harness` key is the only harness switch — a modules-map entry is ignored.
_write_project_config() {
  local state="$1"
  local value=claudecode
  [[ "${state}" == "enabled" ]] && value=opencode

  cat > "${SANDBOX_DIR}/.devbot.project.jsonc" <<JSONC_EOF
{
  "harness": "${value}"
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

@test "sonarqube is on the stale-refresh list (canonical timeout key is new)" {
  # Existing opencode.jsonc entries predate the `timeout` key, so they read as
  # stale and must be dropped for init to re-register them with it.
  run grep -E '^[[:space:]]*REFRESH_MODULES=\(' "${RESET_SCRIPT}"
  assert_success
  [[ "$output" == *"sonarqube"* ]] || fail "sonarqube missing from REFRESH_MODULES: $output"
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
# its plugin/MCP entries unless reset drops them — from BOTH plugin surfaces:
# the root opencode.jsonc (dev-bot-managed) and the opencode-owned
# .opencode/opencode.json (unioned with it). Fixture:
#   - codebase-index disabled via project modules override (module declares
#     plugin.opencode.json = ["opencode-codebase-index"])
#   - react globally disabled (canonical mcp.json declares "react-nextjs-devtools")
#   - enabled modules' entries (on-hooks.ts plugin, chrome-devtools MCP) survive
#   - a user's own plugin entry on the second surface survives

_write_d7_fixture() {
  # opencode enabled; codebase-index (plugin) and react (mcp.json key
  # "react-nextjs-devtools") disabled at project level. chrome-devtools is
  # force-ENABLED at project level too (its MCP entry must survive the prune):
  # the project modules map overrides the real global config, so the test is
  # hermetic — it must not depend on whatever per-machine .devbot.global.jsonc
  # disables (review F4).
  cat > "${SANDBOX_DIR}/.devbot.project.jsonc" <<JSONC_EOF
{
  "harness": "opencode",
  "modules": {
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
        "react-nextjs-devtools": {"type": "local", "command": ["next-devtools-mcp"]},
        "chrome-devtools": entry,
    },
}
with open(sys.argv[3] + "/opencode.jsonc", "w") as f:
    json.dump(config, f, indent=2)
    f.write("\n")

# The opencode-owned second plugin surface. Its plugin array UNIONS with
# opencode.jsonc's, so a disabled module's entry left here keeps the plugin
# loaded even after the root config is pruned — the exact shape of the
# codebase-index flip bug (audit-56). A user's own entry must survive.
project_config = {
    "$schema": "https://opencode.ai/config.json",
    "plugin": ["opencode-codebase-index", "a-user-installed-plugin"],
}
with open(sys.argv[3] + "/.opencode/opencode.json", "w") as f:
    json.dump(project_config, f, indent=2)
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
assert 'react-nextjs-devtools' not in mcp, mcp
assert 'chrome-devtools' in mcp, mcp
# Second plugin surface: the disabled module's entry must be pruned there too,
# while the user's own entry survives.
project = load_jsonc('${SANDBOX_DIR}/.opencode/opencode.json')
pplugins = project.get('plugin', [])
assert 'opencode-codebase-index' not in pplugins, pplugins
assert 'a-user-installed-plugin' in pplugins, pplugins
print('D7-PRUNE:OK')
"
  assert_success
  grep -qF 'D7-PRUNE:OK' <<< "$output" || fail "disabled-module entries not pruned"
}

@test "D7: second reset is byte-idempotent (no further changes)" {
  _write_d7_fixture

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  local after_first after_first_project
  after_first="$(cat "${SANDBOX_DIR}/opencode.jsonc")"
  after_first_project="$(cat "${SANDBOX_DIR}/.opencode/opencode.json")"

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  refute_output --partial "nothing to reset"
  assert_equal "$(cat "${SANDBOX_DIR}/opencode.jsonc")" "${after_first}"
  assert_equal "$(cat "${SANDBOX_DIR}/.opencode/opencode.json")" "${after_first_project}"
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
  "harness": "opencode",
  "modules": {
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

# ── chrome-devtools: the entry must pick up its declared `enabled: false` ────
# Its canonical manifest started declaring `enabled`, which changes the
# translated shape, so entries registered before the field existed are stale and
# must be dropped for init to re-register them disabled. Off the refresh list
# the server stays enabled forever (registration is skip-if-exists).

# _write_chrome_devtools_fixture <stale|current>: chrome-devtools explicitly
# enabled at project level so the test is hermetic. "stale" is the pre-`enabled`
# shape; "current" is generated from the canonical manifest — a hand-written
# literal would read as stale and be pruned.
_write_chrome_devtools_fixture() {
  local mode="$1"

  cat > "${SANDBOX_DIR}/.devbot.project.jsonc" <<JSONC_EOF
{
  "harness": "opencode",
  "modules": {
    "chrome-devtools": true
  }
}
JSONC_EOF

  # Keep a user file so .opencode/ survives reset's empty-directory cleanup
  # (see the playwright fixture above for why this matters).
  mkdir -p "${SANDBOX_DIR}/.opencode/agents"
  echo "# User agent" > "${SANDBOX_DIR}/.opencode/agents/user-agent.md"
  python3 - "${PROJECT_ROOT}/src/_shared" "${PROJECT_ROOT}" "${SANDBOX_DIR}" "${mode}" <<'PY_EOF'
import json, sys
sys.path.insert(0, sys.argv[1])
from mcp_translate import load_canonical, server_map, translate

root, sandbox, mode = sys.argv[2], sys.argv[3], sys.argv[4]
entry = translate(
    server_map(load_canonical(root + "/src/agentic/chrome-devtools/mcp.json"))["chrome-devtools"],
    "opencode",
)
if mode == "stale":
    entry.pop("enabled", None)

with open(sandbox + "/opencode.jsonc", "w") as f:
    json.dump({"mcp": {"chrome-devtools": entry}}, f, indent=2)
    f.write("\n")
PY_EOF
}

@test "chrome-devtools: an entry predating enabled is dropped (on the refresh list)" {
  _write_chrome_devtools_fixture stale

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  run python3 -c "
import sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
mcp = load_jsonc('${SANDBOX_DIR}/opencode.jsonc').get('mcp', {})
assert 'chrome-devtools' not in mcp, mcp
print('CDT-REFRESHED:OK')
"
  assert_success
  grep -qF 'CDT-REFRESHED:OK' <<< "$output" || fail "stale chrome-devtools entry not refreshed"
}

@test "chrome-devtools: the canonical entry is kept (no churn)" {
  _write_chrome_devtools_fixture current

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  run python3 -c "
import sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
entry = load_jsonc('${SANDBOX_DIR}/opencode.jsonc')['mcp']['chrome-devtools']
assert entry.get('enabled') is False, entry
print('CDT-KEPT:OK')
"
  assert_success
  grep -qF 'CDT-KEPT:OK' <<< "$output" || fail "current chrome-devtools entry was churned"
}

# ── dynamic runtime manifests (module emits, harness merges) ────────────────
# A module init writes .opencode/<name>.mcp.json for init-time values (jetbrains'
# detected IDE port); _register_dynamic_mcps merges it append-only. That file is
# a regular file, not a symlink, and a module declaring no canonical
# mcp.json/plugin.opencode.json has no path into the disabled-module prune above
# (jetbrains declares neither) — so disabling it left both the manifest and its
# opencode.jsonc key live across every reinit.

_write_dynamic_manifest_fixture() {
  cat > "${SANDBOX_DIR}/.devbot.project.jsonc" <<'JSONC_EOF'
{
  "harness": "opencode",
  "modules": {
    "jetbrains": false
  }
}
JSONC_EOF

  # Keep .opencode/ non-empty: reset prunes empty dirs, and an empty .opencode/
  # would make the second reset exit before the block under test.
  mkdir -p "${SANDBOX_DIR}/.opencode/agents"
  echo "# User agent" > "${SANDBOX_DIR}/.opencode/agents/user-agent.md"

  # Owned by the disabled module.
  cat > "${SANDBOX_DIR}/.opencode/jetbrains.mcp.json" <<'JSON_EOF'
{"jetbrains": {"type": "remote", "url": "http://127.0.0.1:64442/stream", "enabled": true}}
JSON_EOF

  # Owner not disabled — must survive (guards against over-pruning).
  cat > "${SANDBOX_DIR}/.opencode/other.mcp.json" <<'JSON_EOF'
{"other": {"type": "local", "command": ["other-mcp"]}}
JSON_EOF

  cat > "${SANDBOX_DIR}/opencode.jsonc" <<'JSONC_EOF'
{
  "mcp": {
    "jetbrains": {"type": "remote", "url": "http://127.0.0.1:64442/stream", "enabled": true},
    "other": {"type": "local", "command": ["other-mcp"]}
  }
}
JSONC_EOF
}

@test "D8: reset removes a disabled module's dynamic manifest and its MCP key" {
  _write_dynamic_manifest_fixture

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  refute [ -e "${SANDBOX_DIR}/.opencode/jetbrains.mcp.json" ]
  assert [ -e "${SANDBOX_DIR}/.opencode/other.mcp.json" ]

  run python3 -c "
import sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
mcp = load_jsonc('${SANDBOX_DIR}/opencode.jsonc').get('mcp', {})
assert 'jetbrains' not in mcp, mcp
assert 'other' in mcp, mcp
print('D8-DYNAMIC-PRUNE:OK')
"
  assert_success
  grep -qF 'D8-DYNAMIC-PRUNE:OK' <<< "$output" || fail "disabled module's dynamic manifest not pruned"
}

@test "D8: second reset is byte-idempotent (dynamic manifest prune)" {
  _write_dynamic_manifest_fixture

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  local after_first
  after_first="$(cat "${SANDBOX_DIR}/opencode.jsonc")"

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  refute_output --partial "nothing to reset"
  assert_equal "$(cat "${SANDBOX_DIR}/opencode.jsonc")" "${after_first}"
}

# A dynamic module's registered key can outlive its manifest: the manifest is a
# regular file, so a user or a rebuilt .opencode/ can remove it while the merged
# entry stays in opencode.jsonc. The manifest-keyed prune then has nothing to
# find and the disabled module's server stays live across every reinit.
# Ownership follows the same exact-or-hyphen rule as the manifest filename
# (<name>, <name>-<detail>) — the rule _devbot_manifest_owner_disabled applies.
_write_orphaned_key_fixture() {
  cat > "${SANDBOX_DIR}/.devbot.project.jsonc" <<'JSONC_EOF'
{
  "harness": "opencode",
  "modules": {
    "jetbrains": false
  }
}
JSONC_EOF

  mkdir -p "${SANDBOX_DIR}/.opencode/agents"
  echo "# User agent" > "${SANDBOX_DIR}/.opencode/agents/user-agent.md"

  cat > "${SANDBOX_DIR}/opencode.jsonc" <<'JSONC_EOF'
{
  "mcp": {
    "jetbrains": {"type": "remote", "url": "http://127.0.0.1:64442/stream", "enabled": true},
    "jetbrains-lsp": {"type": "remote", "url": "http://127.0.0.1:64443/stream"},
    "jetbrainstorm": {"type": "remote", "url": "http://127.0.0.1:1/stream"},
    "other": {"type": "local", "command": ["other-mcp"]}
  }
}
JSONC_EOF
}

@test "D9: reset prunes a disabled dynamic module's key when its manifest is gone" {
  _write_orphaned_key_fixture

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  run python3 -c "
import sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
mcp = load_jsonc('${SANDBOX_DIR}/opencode.jsonc').get('mcp', {})
assert 'jetbrains' not in mcp, mcp
assert 'jetbrains-lsp' not in mcp, mcp
assert 'jetbrainstorm' in mcp, mcp
assert 'other' in mcp, mcp
print('D9-ORPHAN-PRUNE:OK')
"
  assert_success
  grep -qF 'D9-ORPHAN-PRUNE:OK' <<< "$output" || fail "orphaned disabled-module key not pruned"
}

@test "D9: second reset is byte-idempotent (orphan prune)" {
  _write_orphaned_key_fixture

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  local after_first
  after_first="$(cat "${SANDBOX_DIR}/opencode.jsonc")"

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  assert_equal "$(cat "${SANDBOX_DIR}/opencode.jsonc")" "${after_first}"
}

@test "D9: a disabled skill-only module does not prune user MCP keys" {
  # frontend ships no mcp.json and writes no runtime manifest: disabling it must
  # not delete a user's servers that happen to share its name.
  cat > "${SANDBOX_DIR}/.devbot.project.jsonc" <<'JSONC_EOF'
{
  "harness": "opencode",
  "modules": {
    "frontend": false
  }
}
JSONC_EOF

  mkdir -p "${SANDBOX_DIR}/.opencode/agents"
  cat > "${SANDBOX_DIR}/opencode.jsonc" <<'JSONC_EOF'
{
  "mcp": {
    "frontend": {"type": "local", "command": ["user-frontend-mcp"]},
    "frontend-docs": {"type": "local", "command": ["user-docs-mcp"]}
  }
}
JSONC_EOF

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  run python3 -c "
import sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
mcp = load_jsonc('${SANDBOX_DIR}/opencode.jsonc').get('mcp', {})
assert 'frontend' in mcp, mcp
assert 'frontend-docs' in mcp, mcp
print('D9-SKILL-ONLY-KEPT:OK')
"
  assert_success
  grep -qF 'D9-SKILL-ONLY-KEPT:OK' <<< "$output" || fail "skill-only module pruned user MCP keys"
}

@test "D9: a disabled harness does not prune user MCP keys" {
  # claudecode rewrites the aggregate .mcp.json but produces no
  # .opencode/claudecode*.mcp.json manifest: disabling it must not delete a
  # user's same-named entries.
  cat > "${SANDBOX_DIR}/.devbot.project.jsonc" <<'JSONC_EOF'
{
  "harness": "opencode"
}
JSONC_EOF

  mkdir -p "${SANDBOX_DIR}/.opencode/agents"
  cat > "${SANDBOX_DIR}/opencode.jsonc" <<'JSONC_EOF'
{
  "mcp": {
    "claudecode": {"type": "local", "command": ["user-claudecode-mcp"]},
    "claudecode-extra": {"type": "local", "command": ["user-extra-mcp"]}
  }
}
JSONC_EOF

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  run python3 -c "
import sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
mcp = load_jsonc('${SANDBOX_DIR}/opencode.jsonc').get('mcp', {})
assert 'claudecode' in mcp, mcp
assert 'claudecode-extra' in mcp, mcp
print('D9-HARNESS-KEPT:OK')
"
  assert_success
  grep -qF 'D9-HARNESS-KEPT:OK' <<< "$output" || fail "disabled harness pruned user MCP keys"
}

@test "D9: reset prunes a disabled netsuite key whose manifest is already gone" {
  # The netsuite module emits netsuite-<account>.mcp.json with no canonical
  # mcp.json, so the orphan path is the only thing that can remove a key left
  # behind when the manifest disappears out of band.
  cat > "${SANDBOX_DIR}/.devbot.project.jsonc" <<'JSONC_EOF'
{
  "harness": "opencode",
  "modules": {
    "netsuite": false
  }
}
JSONC_EOF

  mkdir -p "${SANDBOX_DIR}/.opencode/agents"
  echo "# User agent" > "${SANDBOX_DIR}/.opencode/agents/user-agent.md"

  cat > "${SANDBOX_DIR}/opencode.jsonc" <<'JSONC_EOF'
{
  "mcp": {
    "netsuite-1234567": {"type": "remote", "url": "https://1234567.suitetalk.api.netsuite.com/services/mcp/v1/all", "enabled": false},
    "other": {"type": "local", "command": ["other-mcp"]}
  }
}
JSONC_EOF

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  run python3 -c "
import sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
mcp = load_jsonc('${SANDBOX_DIR}/opencode.jsonc').get('mcp', {})
assert 'netsuite-1234567' not in mcp, mcp
assert 'other' in mcp, mcp
print('D9-NETSUITE-ORPHAN:OK')
"
  assert_success
  grep -qF 'D9-NETSUITE-ORPHAN:OK' <<< "$output" || fail "disabled netsuite's orphan key survived"
}

@test "D9: reset prunes a disabled datasources key whose manifest is already gone" {
  # datasources wires each source under the short `ds-<source>` prefix its
  # mcp.dynamic.json declares, while the manifest keeps the module's name
  # (datasources-<source>.mcp.json) so the harness can still attribute it. With
  # the manifest gone, only that declaration identifies the orphan key.
  cat > "${SANDBOX_DIR}/.devbot.project.jsonc" <<'JSONC_EOF'
{
  "harness": "opencode",
  "modules": {
    "datasources": false
  }
}
JSONC_EOF

  mkdir -p "${SANDBOX_DIR}/.opencode/agents"
  echo "# User agent" > "${SANDBOX_DIR}/.opencode/agents/user-agent.md"

  cat > "${SANDBOX_DIR}/opencode.jsonc" <<'JSONC_EOF'
{
  "mcp": {
    "ds-mariadb-dev": {"type": "remote", "url": "http://127.0.0.1:18510/mcp/mariadb-dev", "enabled": false},
    "datasources-legacy": {"type": "remote", "url": "http://127.0.0.1:18510/mcp/legacy"},
    "other": {"type": "local", "command": ["other-mcp"]}
  }
}
JSONC_EOF

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  run python3 -c "
import sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
mcp = load_jsonc('${SANDBOX_DIR}/opencode.jsonc').get('mcp', {})
assert 'ds-mariadb-dev' not in mcp, mcp
assert 'datasources-legacy' not in mcp, mcp
assert 'other' in mcp, mcp
print('D9-DATASOURCES-ORPHAN:OK')
"
  assert_success
  grep -qF 'D9-DATASOURCES-ORPHAN:OK' <<< "$output" || fail "disabled datasources' orphan key survived"
}

# D10: a module's server keys are not always its name. The k8s module writes
# `k8s-<cluster>.mcp.json` (the filename keeps the module's name, which is how a
# disabled module's manifests are found) while the server key inside is
# `kctl-<cluster>`. Disabling the module must take both — the generated
# kubeconfig outlives the module, so a leftover key is a live server.
_write_prefixed_key_fixture() {
  cat > "${SANDBOX_DIR}/.devbot.project.jsonc" <<'JSONC_EOF'
{
  "harness": "opencode",
  "modules": {
    "k8s": false
  }
}
JSONC_EOF

  mkdir -p "${SANDBOX_DIR}/.opencode/agents"
  echo "# User agent" > "${SANDBOX_DIR}/.opencode/agents/user-agent.md"

  cat > "${SANDBOX_DIR}/.opencode/k8s-demo.mcp.json" <<'JSON_EOF'
{"kctl-demo": {"type": "local", "command": ["bash", "-c", "true"]}}
JSON_EOF

  cat > "${SANDBOX_DIR}/opencode.jsonc" <<'JSONC_EOF'
{
  "mcp": {
    "kctl-demo": {"type": "local", "command": ["bash", "-c", "true"]},
    "other": {"type": "local", "command": ["other-mcp"]}
  }
}
JSONC_EOF
}

@test "D10: reset prunes a disabled module's servers whose keys differ from its name" {
  _write_prefixed_key_fixture

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  refute [ -e "${SANDBOX_DIR}/.opencode/k8s-demo.mcp.json" ]
  run python3 -c "
import sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
mcp = load_jsonc('${SANDBOX_DIR}/opencode.jsonc').get('mcp', {})
assert 'kctl-demo' not in mcp, mcp
assert 'other' in mcp, mcp
print('D10-PREFIXED-PRUNE:OK')
"
  assert_success
  grep -qF 'D10-PREFIXED-PRUNE:OK' <<< "$output" || fail "prefixed server key not pruned"
}

@test "D10: second reset is byte-idempotent (prefixed key prune)" {
  _write_prefixed_key_fixture

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  local after_first
  after_first="$(cat "${SANDBOX_DIR}/opencode.jsonc")"

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  assert_equal "$(cat "${SANDBOX_DIR}/opencode.jsonc")" "${after_first}"
}

@test "D10: reset prunes a kctl key whose manifest is already gone" {
  # The manifest is a regular file, so it can be removed before reset runs
  # (a rebuilt .opencode/, a user tidying up) while the merged key stays. The
  # key is not named after the module, so only the declared prefix finds it.
  cat > "${SANDBOX_DIR}/.devbot.project.jsonc" <<'JSONC_EOF'
{
  "harness": "opencode",
  "modules": {
    "k8s": false
  }
}
JSONC_EOF

  mkdir -p "${SANDBOX_DIR}/.opencode/agents"
  echo "# User agent" > "${SANDBOX_DIR}/.opencode/agents/user-agent.md"

  cat > "${SANDBOX_DIR}/opencode.jsonc" <<'JSONC_EOF'
{
  "mcp": {
    "kctl-demo": {"type": "local", "command": ["bash", "-c", "true"]},
    "kctl-other": {"type": "local", "command": ["bash", "-c", "true"]},
    "other": {"type": "local", "command": ["other-mcp"]}
  }
}
JSONC_EOF

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  run python3 -c "
import sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
mcp = load_jsonc('${SANDBOX_DIR}/opencode.jsonc').get('mcp', {})
assert 'kctl-demo' not in mcp, mcp
assert 'kctl-other' not in mcp, mcp
assert 'other' in mcp, mcp
print('D10-ORPHAN-PRUNE:OK')
"
  assert_success
  grep -qF 'D10-ORPHAN-PRUNE:OK' <<< "$output" || fail "orphaned kctl key not pruned"
}

# ── D11: a RETIRED key is pruned whatever the module's state ─────────────────
# A server dev-bot itself renamed leaves an orphan no other sweep can find: the
# module's canonical mcp.json no longer declares the old name, so neither the
# stale-refresh loop nor the disabled-module prune matches it. The ENABLED
# module is the case that used to leak, so react is enabled here.
@test "D11: reset prunes a retired MCP key while its module is enabled" {
  cat > "${SANDBOX_DIR}/.devbot.project.jsonc" <<'JSONC_EOF'
{
  "harness": "opencode",
  "modules": {
    "react": true
  }
}
JSONC_EOF

  mkdir -p "${SANDBOX_DIR}/.opencode/agents"
  echo "# User agent" > "${SANDBOX_DIR}/.opencode/agents/user-agent.md"

  cat > "${SANDBOX_DIR}/opencode.jsonc" <<'JSONC_EOF'
{
  "mcp": {
    "next-devtools": {"type": "local", "command": ["next-devtools-mcp"]},
    "react-nextjs-devtools": {"type": "local", "command": ["npx", "-y", "next-devtools-mcp@latest"], "enabled": false},
    "other": {"type": "local", "command": ["other-mcp"]}
  }
}
JSONC_EOF

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  run python3 -c "
import sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
mcp = load_jsonc('${SANDBOX_DIR}/opencode.jsonc').get('mcp', {})
assert 'next-devtools' not in mcp, mcp
assert 'react-nextjs-devtools' in mcp, mcp
assert 'other' in mcp, mcp
print('D11-RETIRED-KEY:OK')
"
  assert_success
  grep -qF 'D11-RETIRED-KEY:OK' <<< "$output" || fail "retired MCP key survived the reset"
}

# ── D12: a RETIRED key PREFIX is pruned ──────────────────────────────────────
# datasources' server keys moved from `datasources-<source>` to `ds-<source>`.
# The old family is unbounded, so an exact-key list cannot name it, and the
# disabled-module prune only sweeps it while datasources is DISABLED. It is
# enabled here, so only a prefix sweep can clear the orphans — and it must
# leave the current `ds-` keys and an unrelated server alone.
_write_retired_prefix_fixture() {
  cat > "${SANDBOX_DIR}/.devbot.project.jsonc" <<'JSONC_EOF'
{
  "harness": "opencode",
  "modules": {
    "datasources": true
  }
}
JSONC_EOF

  mkdir -p "${SANDBOX_DIR}/.opencode/agents"
  echo "# User agent" > "${SANDBOX_DIR}/.opencode/agents/user-agent.md"

  cat > "${SANDBOX_DIR}/opencode.jsonc" <<'JSONC_EOF'
{
  "mcp": {
    "datasources-mariadb-dev": {"type": "remote", "url": "http://127.0.0.1:18510/mcp/mariadb-dev"},
    "datasources-legacy": {"type": "remote", "url": "http://127.0.0.1:18510/mcp/legacy"},
    "ds-mariadb-dev": {"type": "remote", "url": "http://127.0.0.1:18510/mcp/mariadb-dev"},
    "other": {"type": "local", "command": ["other-mcp"]}
  }
}
JSONC_EOF
}

@test "D12: reset prunes retired MCP key prefixes and keeps current ones" {
  _write_retired_prefix_fixture

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  run python3 -c "
import sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
mcp = load_jsonc('${SANDBOX_DIR}/opencode.jsonc').get('mcp', {})
assert 'datasources-mariadb-dev' not in mcp, mcp
assert 'datasources-legacy' not in mcp, mcp
assert 'ds-mariadb-dev' in mcp, mcp
assert 'other' in mcp, mcp
print('D12-RETIRED-PREFIX:OK')
"
  assert_success
  grep -qF 'D12-RETIRED-PREFIX:OK' <<< "$output" || fail "retired MCP key prefix survived the reset"
}

@test "D12: second reset is byte-idempotent (retired key prefix prune)" {
  _write_retired_prefix_fixture

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  local after_first
  after_first="$(cat "${SANDBOX_DIR}/opencode.jsonc")"

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  assert_equal "$(cat "${SANDBOX_DIR}/opencode.jsonc")" "${after_first}"
}

# ── D13: a config-only project is swept too ─────────────────────────────────
# reset exits early when .opencode/ is absent, which is right for the symlink
# cleanup but wrong for config pruning: a project can carry a dev-bot-managed
# opencode.jsonc with no symlink farm, and the retirement must still happen.
@test "D13: reset prunes retired keys without an .opencode directory" {
  cat > "${SANDBOX_DIR}/.devbot.project.jsonc" <<'JSONC_EOF'
{
  "harness": "opencode",
  "modules": {
    "react": true
  }
}
JSONC_EOF
  # Deliberately no .opencode/ directory.

  cat > "${SANDBOX_DIR}/opencode.jsonc" <<'JSONC_EOF'
{
  "mcp": {
    "next-devtools": {"type": "local", "command": ["next-devtools-mcp"]},
    "other": {"type": "local", "command": ["other-mcp"]}
  }
}
JSONC_EOF

  run bash "${RESET_SCRIPT}" "${SANDBOX_DIR}"
  assert_success

  run python3 -c "
import sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
mcp = load_jsonc('${SANDBOX_DIR}/opencode.jsonc').get('mcp', {})
assert 'next-devtools' not in mcp, mcp
assert 'other' in mcp, mcp
print('D13-CONFIG-ONLY:OK')
"
  assert_success
  grep -qF 'D13-CONFIG-ONLY:OK' <<< "$output" || fail "retired key survived in a config-only project"
}
