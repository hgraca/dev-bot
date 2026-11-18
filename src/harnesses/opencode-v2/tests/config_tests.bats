#!/usr/bin/env bats
# =============================================================================
# src/harnesses/opencode-v2/tests/config_tests.bats
# Tests lib/v2config.py — the textual edits that write the v2 config shapes.
#
# Every edit must be idempotent and comment-preserving: opencode.jsonc is seeded
# once and then belongs to the project, so a reinit that changes nothing has to
# write nothing.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  V2_ROOT="$(cd "${MODULE_DIR}/../../.." && pwd)"
  HELPER="${MODULE_DIR}/lib/v2config.py"

  WORK="$(mktemp -d)"
  CONFIG="${WORK}/opencode.jsonc"
  cp "${MODULE_DIR}/opencode-v2.dist.jsonc" "${CONFIG}"
  export V2_SHARED_DIR="${V2_ROOT}/src/_shared"
}

teardown() {
  rm -rf "${WORK}"
}

v2() {
  python3 "${HELPER}" "$@"
}

_valid_jsonc() {
  python3 -c "
import sys; sys.path.insert(0, '${V2_ROOT}/src/_shared')
from read_jsonc import load_jsonc
load_jsonc('${CONFIG}')"
}

@test "get reads a top-level key printed as JSON" {
  run v2 get "${CONFIG}" instructions
  assert_success
  assert_output --partial '.agents/memory/active/**/*.md'
}

@test "has-legacy is quiet on a v2 config" {
  run v2 has-legacy "${CONFIG}"
  assert_failure
}

@test "has-legacy names every v1 key" {
  cat > "${CONFIG}" <<'EOF'
{ "plugin": [], "permission": {}, "agent": {}, "mcp": { "x": { "enabled": true } } }
EOF
  run v2 has-legacy "${CONFIG}"
  assert_success
  assert_output --partial "plugin"
  assert_output --partial "permission"
  assert_output --partial "agent"
  assert_output --partial "mcp"
}

@test "upsert-plugin adds an entry once and is idempotent" {
  v2 upsert-plugin "${CONFIG}" './.opencode/v2/plugins/demo'
  local first
  first="$(md5sum "${CONFIG}" | cut -d' ' -f1)"
  v2 upsert-plugin "${CONFIG}" './.opencode/v2/plugins/demo'
  assert_equal "$(md5sum "${CONFIG}" | cut -d' ' -f1)" "${first}"
  run v2 get "${CONFIG}" plugins
  assert_output --partial 'plugins/demo'
}

@test "remove-plugin restores the block and leaves the file valid" {
  v2 upsert-plugin "${CONFIG}" './.opencode/v2/plugins/demo'
  v2 remove-plugin "${CONFIG}" './.opencode/v2/plugins/demo'
  run v2 get "${CONFIG}" plugins
  refute_output --partial 'plugins/demo'
  _valid_jsonc
}

@test "plugin add/remove cycles leave no blank lines behind" {
  v2 upsert-plugin "${CONFIG}" './.opencode/v2/plugins/a'
  v2 remove-plugin "${CONFIG}" './.opencode/v2/plugins/a'
  v2 upsert-plugin "${CONFIG}" './.opencode/v2/plugins/a'
  v2 remove-plugin "${CONFIG}" './.opencode/v2/plugins/a'
  python3 - "${CONFIG}" <<'PY'
import sys
text = open(sys.argv[1]).read()
block = text[text.find('"plugins"'):text.find("]", text.find('"plugins"'))]
assert "\n\n" not in block, f"blank line accumulated: {block!r}"
PY
}

@test "merge-mcp inserts into mcp.servers and is idempotent" {
  v2 merge-mcp "${CONFIG}" demo '{"type":"local","command":["echo"]}'
  run v2 get "${CONFIG}" mcp.servers
  assert_output --partial '"demo"'
  local first
  first="$(md5sum "${CONFIG}" | cut -d' ' -f1)"
  v2 merge-mcp "${CONFIG}" demo '{"type":"local","command":["echo"]}'
  assert_equal "$(md5sum "${CONFIG}" | cut -d' ' -f1)" "${first}"
}

@test "merge-mcp creates the mcp block when the seed predates it" {
  echo '{ "plugins": [] }' > "${CONFIG}"
  v2 merge-mcp "${CONFIG}" demo '{"type":"local","command":["echo"]}'
  run v2 get "${CONFIG}" mcp.servers
  assert_output --partial '"demo"'
}

@test "remove-mcp drops the server and keeps the file valid" {
  v2 merge-mcp "${CONFIG}" demo '{"type":"local","command":["echo"]}'
  v2 remove-mcp "${CONFIG}" demo
  run v2 get "${CONFIG}" mcp.servers
  refute_output --partial '"demo"'
  _valid_jsonc
}

@test "set-mcp-disabled flips the flag in place" {
  v2 merge-mcp "${CONFIG}" demo '{"type":"local","command":["echo"]}'
  v2 set-mcp-disabled "${CONFIG}" demo true
  run v2 get "${CONFIG}" mcp.servers
  assert_output --partial '"disabled": true'
  # Already correct is success: mcp-sync.ts treats a 0 as "the file holds the
  # wanted value" and only retries a real failure.
  run v2 set-mcp-disabled "${CONFIG}" demo true
  assert_success
  _valid_jsonc
}

@test "set-mcp-disabled reports a server this config does not declare" {
  # Exit 2: a global server. The project file must not invent an entry for it,
  # and the sync must not treat it as a failed write.
  run v2 set-mcp-disabled "${CONFIG}" absent true
  assert_equal "$status" 2
  _valid_jsonc
}

@test "the helper locates src/_shared without V2_SHARED_DIR" {
  # mcp-sync.ts spawns this helper from the running host, which does not carry
  # the environment init.sh sets. Without the fallback the read_jsonc import
  # failed, every MCP toggle wrote nothing, and the hook retried every 2s.
  v2 merge-mcp "${CONFIG}" demo '{"type":"local","command":["echo"]}'

  run env -u V2_SHARED_DIR python3 "${HELPER}" set-mcp-disabled "${CONFIG}" demo true
  assert_success

  run v2 get "${CONFIG}" mcp.servers
  assert_output --partial '"disabled": true'
  _valid_jsonc
}

@test "ensure-external-directory reports no work on the shipped dist" {
  run v2 ensure-external-directory "${CONFIG}"
  assert_success
  assert_output ""
}

@test "ensure-external-directory adds a missing rule" {
  python3 - "${CONFIG}" "${V2_ROOT}/src/_shared" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[2])
from read_jsonc import load_jsonc
cfg = load_jsonc(sys.argv[1])
cfg["permissions"] = [r for r in cfg["permissions"] if r["action"] != "external_directory"]
json.dump(cfg, open(sys.argv[1], "w"), indent=2)
PY
  run v2 ensure-external-directory "${CONFIG}"
  assert_success
  assert_output "1"
  run v2 get "${CONFIG}" permissions
  assert_output --partial '"resource": "*"'
  assert_output --partial '"resource": "/tmp/**"'
}

@test "set-default-agent rewrites an existing value" {
  v2 set-default-agent "${CONFIG}" devbot
  run v2 get "${CONFIG}" default_agent
  assert_output '"devbot"'
  _valid_jsonc
}

@test "remove-tui-plugin removes one entry and keeps the rest" {
  # tui.json's array is singular `plugin`; a v1 seed's entries are retired one by
  # one so a project's own plugin stays.
  local tui="${WORK}/tui.json"
  cat > "${tui}" <<'EOF'
{
  "plugin_enabled": { "internal:sidebar-context": false },
  "plugin": ["opencode-tabs@0.3.0", "opencode-mine@1.0.0"]
}
EOF
  run v2 remove-tui-plugin "${tui}" "opencode-tabs@0.3.0"
  assert_success
  run python3 "${V2_ROOT}/src/_shared/read_jsonc.py" "${tui}" plugin
  refute_output --partial 'opencode-tabs'
  assert_output --partial 'opencode-mine@1.0.0'
}

@test "remove-tui-plugin is a no-op on a missing entry" {
  local tui="${WORK}/tui.json"
  printf '{ "plugin": ["a@1.0.0"] }\n' > "${tui}"
  run v2 remove-tui-plugin "${tui}" "b@2.0.0"
  assert_failure
}

# ── merge-mcps: a server set in one process ───────────────────────────────────
# The harness registers every enabled module's servers through this call instead
# of one `merge-mcp` per server.

@test "merge-mcps inserts a whole set and reports the keys it added" {
  run v2 merge-mcps "${CONFIG}" '{"alpha":{"type":"local","command":["a"]},"beta":{"type":"remote","url":"http://b.test/mcp"}}'
  assert_success
  assert_equal "${output}" "$(printf 'alpha\nbeta')"

  run v2 get "${CONFIG}" mcp.servers.alpha
  assert_output --partial '"command": ["a"]'
  run v2 get "${CONFIG}" mcp.servers.beta
  assert_output --partial 'http://b.test/mcp'
}

@test "merge-mcps leaves an existing server alone and does not report it" {
  v2 merge-mcp "${CONFIG}" alpha '{"type":"local","command":["original"]}' >/dev/null

  run v2 merge-mcps "${CONFIG}" '{"alpha":{"type":"local","command":["replacement"]},"beta":{"type":"remote","url":"http://b.test/mcp"}}'
  assert_success
  assert_equal "${output}" "beta"

  run v2 get "${CONFIG}" mcp.servers.alpha
  assert_output --partial '"original"'
}

@test "merge-mcps keeps going when one entry cannot be written" {
  # `write` renames a temp file over the config, so the directory is what has to
  # be unwritable. The call must still exit 0 and leave the file alone rather
  # than aborting the caller's whole registration pass.
  local before
  before="$(cat "${CONFIG}")"
  chmod 555 "${WORK}"

  run v2 merge-mcps "${CONFIG}" '{"alpha":{"type":"local","command":["a"]},"beta":{"type":"remote","url":"http://b.test/mcp"}}'
  chmod 755 "${WORK}"

  assert_success
  assert_equal "${output}" ""
  assert_equal "$(cat "${CONFIG}")" "${before}"
}
