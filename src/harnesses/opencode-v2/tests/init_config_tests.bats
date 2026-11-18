#!/usr/bin/env bats
# =============================================================================
# src/harnesses/opencode-v2/tests/init_config_tests.bats
# the v2 config it seeds, and the v1 config it migrates.
#
# Auto-loaded plugin entries, MCP cwd pinning, the retired TUI list, the pre-v2
# backup, and the package.json / bun-pty ownership rules.
#
# Split from init_tests.bats: bats parallelises across files only, and that file
# backed the suite's wall clock. Scenarios and seeds come from init_test_helper.
# =============================================================================

load "${BATS_TEST_DIRNAME}/../../../_shared/tests/lib/scenario"
load 'init_test_helper'

@test "init seeds the v2 config shapes" {
  scenario default
  assert [ -f "${CONFIG}" ]
  run v2 has-legacy "${CONFIG}"
  assert_failure
  run v2 get "${CONFIG}" permissions
  assert_output --partial '"action": "external_directory"'
}

@test "init is byte-idempotent across repeated runs" {
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  local first
  first="$(md5sum "${CONFIG}" | cut -d' ' -f1)"
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  assert_equal "$(md5sum "${CONFIG}" | cut -d' ' -f1)" "${first}"
}

@test "init links each plugin as a directory package" {
  scenario default
  local name entry
  for name in on-hooks mcp-sync; do
    assert [ -d "${PROJECT}/.opencode/plugins/${name}" ]
    entry="${PROJECT}/.opencode/plugins/${name}/index.ts"
    # MUST be a real file: v2 skips a symlinked plugin entry silently.
    assert [ -f "${entry}" ]
    refute [ -L "${entry}" ]
    grep -q "dev-bot: generated opencode-v2 plugin shim" "${entry}"
    grep -q 'export { default } from ' "${entry}"
  done
}

@test "init leaves auto-loaded plugins out of the config" {
  # v2 auto-loads every directory under .opencode/plugins/. A config entry for
  # one registers the plugin twice and the host fails the second copy with
  # "Duplicate plugin ID", which the TUI reports as a failed plugin.
  scenario default
  run v2 get "${CONFIG}" plugins
  assert_success
  refute_output --partial 'plugins/on-hooks'
  refute_output --partial 'plugins/mcp-sync'
}

@test "init drops config entries for auto-loaded plugins" {
  # A config seeded before the rule changed carries them; init must converge.
  scenario_copy default
  v2 upsert-plugin "${CONFIG}" ".opencode/plugins/on-hooks" >/dev/null
  v2 upsert-plugin "${CONFIG}" ".opencode/plugins/mine" >/dev/null
  v2 upsert-plugin "${CONFIG}" "opencode-some-package@1.2.3" >/dev/null

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  run v2 get "${CONFIG}" plugins
  refute_output --partial '.opencode/plugins/'
  assert_output --partial 'opencode-some-package@1.2.3'
}


@test "init leaves root-level module assets alone" {
  # The sweep must only touch the harness-owned farms: .opencode/ root also
  # holds module MCP wrappers, and deleting those breaks them with exit 127.
  scenario root-asset

  assert [ -L "${PROJECT}/.opencode/tools-mcp-serve.sh" ]
}

@test "init retires the v1 v2/ plugin farm including its nested dir" {
  # A leftover `.opencode/v2/plugins/` (from an earlier layout) must not survive:
  # rmdir is non-recursive, so the parent only goes once the child is gone.
  scenario v2-farm _seed_v2_farm
  refute [ -d "${PROJECT}/.opencode/v2" ]
}

@test "every plugin directory carries a package.json" {
  scenario default
  local name
  for name in on-hooks mcp-sync; do
    assert [ -f "${PROJECT}/.opencode/plugins/${name}/package.json" ]
    python3 -c "
import json,sys
d=json.load(open('${PROJECT}/.opencode/plugins/${name}/package.json'))
assert d['name'].startswith('devbot-'), d
assert 'exports' in d, d
"
  done
}

@test "init retires the pty package an earlier build linked" {
  # The PTY extension is no longer shipped: required-plugins.jsonc dropped it, so
  # a stale shim package has to be removed or the host keeps auto-loading it.
  scenario pty-package

  refute [ -e "${PROJECT}/.opencode/plugins/pty" ]
}

@test "init drops a bun-pty dependency it recorded as its own" {
  # The retired PTY extension was its only consumer. The ownership record is what
  # keeps the edit from touching a dependency the project declared.
  mkdir -p "${PROJECT}/.opencode"
  printf '{ "dependencies": { "bun-pty": "^0.4.10" } }\n' > "${PROJECT}/.opencode/package.json"
  printf 'bun-pty\n' > "${PROJECT}/.opencode/.devbot-managed-deps"

  run bash "${MODULE_DIR}/init.sh" "${PROJECT}"
  assert_success
  assert_output --partial "Dropped bun-pty"

  run python3 -c "import json; print(json.load(open('${PROJECT}/.opencode/package.json')).get('dependencies', {}))"
  refute_output --partial "bun-pty"
  [ ! -e "${PROJECT}/.opencode/.devbot-managed-deps" ]
}

@test "a package.json the project already had is not claimed" {
  scenario existing-package

  [ ! -e "${PROJECT}/.opencode/.devbot-managed-deps" ]
  run python3 -c "import json; print(json.load(open('${PROJECT}/.opencode/package.json')).get('dependencies', {}))"
  assert_output --partial "bun-pty"
}

@test "init pins local MCP servers to the project directory" {
  scenario_copy default
  # A local server carried over from a migrated v1 config has no cwd, and v2
  # spawns it outside the project — its relative wrapper path then exits 127.
  v2 merge-mcp "${CONFIG}" demo '{"type":"local","command":["bash","x.sh"]}'

  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null

  run python3 "${MODULE_DIR}/lib/v2config.py" get "${CONFIG}" mcp.servers.demo.cwd
  assert_success
  assert_output --partial "${PROJECT}"
}

@test "init sweeps a dev-bot symlink and keeps user files" {
  scenario sweep

  refute [ -e "${PROJECT}/.opencode/plugins/gone.ts" ]
  assert [ -f "${PROJECT}/.opencode/plugins/mine.ts" ]
}

@test "init drops the emptied v1 plugin farms" {
  scenario tui-farms

  refute [ -d "${PROJECT}/.opencode/tui-plugins" ]
}

@test "init retires the v1 TUI plugin list and keeps the rest" {
  # opencode 2.3 still applies a project tui.json. Its v1 seed re-declared
  # opencode-tabs@0.3.0 (rejected by 2.3's TUI module validator) and three
  # ./tui-plugins/* paths this harness no longer links.
  scenario tui-json

  run python3 "${DEV_BOT_ROOT}/src/_shared/read_jsonc.py" "${PROJECT}/.opencode/tui.json" plugin
  refute_output --partial 'opencode-tabs'
  refute_output --partial 'tui-plugins'
  assert_output --partial 'opencode-mine@1.0.0'
  run python3 "${DEV_BOT_ROOT}/src/_shared/read_jsonc.py" "${PROJECT}/.opencode/tui.json" plugin_enabled
  assert_output --partial 'internal:sidebar-context'
}

@test "init migrates a v1 config and leaves a backup" {
  git -C "${PROJECT}" init -q
  cat > "${CONFIG}" <<'EOF'
{
  "model": "p/m",
  "plugin": ["a-plugin", ["./x.ts", {"k": 1}], ".opencode/plugins/on-hooks.ts", "opencode-pty@0.3.6"],
  "permission": {"bash": {"*": "allow", "sudo *": "ask"}, "edit": "allow", "list": "allow"},
  "agent": {"devbot": {"model": "p/m", "variant": "high"}, "plan": {"disable": true}},
  "provider": {"p": {"npm": "@x/y", "options": {"t": 1}}},
  "mcp": {"s": {"type": "local", "command": ["c"], "enabled": false}},
  "lsp": true
}
EOF
  run bash "${MODULE_DIR}/init.sh" "${PROJECT}"
  assert_success

  assert [ -f "${CONFIG}.pre-v2.bak" ]
  # The backup must not linger as an untracked file in the consumer's repo.
  run git -C "${PROJECT}" check-ignore -v opencode.jsonc.pre-v2.bak
  assert_success
  assert_output --partial "opencode.jsonc.pre-v2.bak"
  run grep -c "DEVBOT - config backup" "${PROJECT}/.gitignore"
  assert_output "2"
  run v2 has-legacy "${CONFIG}"
  assert_failure

  run v2 get "${CONFIG}" permissions
  assert_output --partial '"action": "shell"'
  assert_output --partial '"resource": "sudo *"'
  refute_output --partial '"action": "list"'

  run v2 get "${CONFIG}" mcp.servers
  assert_output --partial '"disabled": true'
  refute_output --partial '"enabled"'

  run v2 get "${CONFIG}" agents
  assert_output --partial '"model": "p/m#high"'
  assert_output --partial '"disabled": true'

  run v2 get "${CONFIG}" providers
  assert_output --partial '"package": "@x/y"'
  assert_output --partial '"settings"'
}

# ── Modules this harness provides natively ───────────────────────────────────
# OpenCode 2.x ships its own websearch tool, so the devbot module would only add
# a duplicate MCP server (one tool, plus its schema and instruction block in
# every session). The exclusion is unconditional — the module's enabled flag
# cannot bring it back — and reinit says why, once.

@test "websearch: not registered when the module is enabled" {
  printf '{ "harness": "opencode-v2", "modules": { "websearch": true } }\n' > "${PROJECT}/.devbot.project.jsonc"

  run bash "${MODULE_DIR}/init.sh" "${PROJECT}"
  assert_success
  assert_output --partial "built-in websearch tool"

  run v2 get "${CONFIG}" "mcp.servers.websearch"
  assert_output ""
}

@test "websearch: not registered when the module is disabled either" {
  # The ignore is unconditional, not a consequence of enablement: no config
  # flip may re-enable it on this harness.
  printf '{ "harness": "opencode-v2", "modules": { "websearch": false } }\n' > "${PROJECT}/.devbot.project.jsonc"

  run bash "${MODULE_DIR}/init.sh" "${PROJECT}"
  assert_success
  assert_output --partial "built-in websearch tool"

  run v2 get "${CONFIG}" "mcp.servers.websearch"
  assert_output ""
}

@test "websearch: an entry an earlier init wrote is removed" {
  # merge-mcp is add-only, so an existing entry survives registration; the
  # exclusion has to retire it or the duplicate server stays live. Seed it the
  # way an earlier devbot would have: config first, then the entry.
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  # The module's own URL is what makes the entry dev-bot's rather than the
  # project's, so seed exactly that (the ownership test below covers the other
  # case).
  local canonical_url
  canonical_url="$(python3 "${DEV_BOT_ROOT}/src/_shared/read_jsonc.py" \
    "${DEV_BOT_ROOT}/src/agentic/websearch/mcp.json" mcp websearch url)"
  v2 merge-mcp "${CONFIG}" websearch "{\"type\":\"remote\",\"url\":\"${canonical_url}\"}"

  run bash "${MODULE_DIR}/init.sh" "${PROJECT}"
  assert_success
  assert_output --partial "removed the MCP entry this harness provides natively"

  run v2 get "${CONFIG}" "mcp.servers.websearch"
  assert_output ""
}

@test "websearch: a server the project configured itself survives" {
  # Ownership is decided on the module's own URL: a project may run its own MCP
  # service under that name, and deleting it on every reinit would be worse than
  # the duplicate this exclusion removes.
  bash "${MODULE_DIR}/init.sh" "${PROJECT}" >/dev/null
  v2 merge-mcp "${CONFIG}" websearch '{"type":"remote","url":"https://search.example.test/mcp"}'

  run bash "${MODULE_DIR}/init.sh" "${PROJECT}"
  assert_success
  assert_output --partial "left your own 'websearch' MCP server in place"

  run v2 get "${CONFIG}" "mcp.servers.websearch.url"
  assert_output --partial "search.example.test"
}

@test "websearch: the notice is printed once per run" {
  run bash "${MODULE_DIR}/init.sh" "${PROJECT}"
  assert_success
  [ "$(printf '%s\n' "${output}" | grep -c 'built-in websearch tool')" -eq 1 ]
}

@test "websearch: the exclusion is a list, not a blanket MCP skip" {
  run bash "${MODULE_DIR}/init.sh" "${PROJECT}"
  assert_success
  # A module this harness does not provide natively is still registered.
  run v2 get "${CONFIG}" "mcp.servers"
  assert_output --partial "devbot-tools"
  refute_output --partial "websearch"
}

# ── the install root is established, not inherited ───────────────────────────
# init.sh sources _shared through $DEV_BOT_ROOT; reading it before defaulting
# meant only a shell that happens to export it survived `set -u`.

@test "init runs without DEV_BOT_ROOT in the environment" {
  # Uses the test's own empty project rather than a scenario: the subject is the
  # environment init starts in, so it must be the only thing being varied.
  run env -u DEV_BOT_ROOT bash "${MODULE_DIR}/init.sh" "${PROJECT}"
  assert_success
  assert [ -f "${CONFIG}" ]
}
