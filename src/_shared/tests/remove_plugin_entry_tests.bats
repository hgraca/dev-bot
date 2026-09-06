#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/remove_plugin_entry_tests.bats
# Tests for remove_plugin_entry.py — removes a plugin name from the top-level
# "plugin" array of an opencode.jsonc config (text surgery, byte-preserving).
#
# Context (D7): opencode plugin registration is append-only (_upsert_opencode_plugin).
# When a module becomes disabled — e.g. codebase-index after a
# codebase_index_provider flip to codebase-memory — reset.sh must drop the
# module's plugin entries so the losing engine is not left half-registered.
# Only the targeted element disappears; comments, layout, and sibling entries
# stay byte-for-byte (audit-32 reinit byte-idempotency).
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"
  TOOL="${PROJECT_ROOT}/src/_shared/remove_plugin_entry.py"

  WORK="$(mktemp -d)"
}

teardown() {
  rm -rf "$WORK" 2>/dev/null || true
}

_write_default() {
  cat > "$WORK/opencode.jsonc" <<'JSONC_EOF'
{
  // opencode runtime config
  "plugin": ["opencode-codebase-index", ".opencode/plugins/on-hooks.ts", "user-plugin"]
}
JSONC_EOF
}

@test "removes a plugin from the plugin array, keeping siblings" {
  _write_default

  run python3 "$TOOL" "$WORK/opencode.jsonc" "opencode-codebase-index"
  assert_success

  run python3 -c "
import json, sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
d = load_jsonc('${WORK}/opencode.jsonc')
plugins = d.get('plugin', [])
assert 'opencode-codebase-index' not in plugins, plugins
assert '.opencode/plugins/on-hooks.ts' in plugins, plugins
assert 'user-plugin' in plugins, plugins
print('PLUGIN-REMOVE:OK')
"
  assert_success
  grep -qF 'PLUGIN-REMOVE:OK' <<< "$output" || fail "plugin not removed from array"
}

@test "absent plugin is an idempotent no-op (exit 0, file unchanged)" {
  _write_default
  local before
  before="$(cat "$WORK/opencode.jsonc")"

  run python3 "$TOOL" "$WORK/opencode.jsonc" "does-not-exist"
  assert_success

  assert_equal "$(cat "$WORK/opencode.jsonc")" "$before"
}

@test "missing file is an idempotent no-op (exit 0)" {
  run python3 "$TOOL" "$WORK/nope.jsonc" "opencode-codebase-index"
  assert_success
}

@test "no plugin array is an idempotent no-op (exit 0)" {
  cat > "$WORK/opencode.jsonc" <<'JSONC_EOF'
{
  "mcp": { "qmd": { "type": "local", "command": ["qmd", "mcp"] } }
}
JSONC_EOF

  run python3 "$TOOL" "$WORK/opencode.jsonc" "opencode-codebase-index"
  assert_success
}

@test "removal preserves comments and formatting of untouched entries" {
  cat > "$WORK/opencode.jsonc" <<'JSONC_EOF'
{
  // opencode runtime config — do not edit by hand
  "plugin": [
    "opencode-codebase-index",
    ".opencode/plugins/on-hooks.ts"
  ]
}
JSONC_EOF

  run python3 "$TOOL" "$WORK/opencode.jsonc" "opencode-codebase-index"
  assert_success

  # Comment survives; sibling keeps its formatting; removed entry is gone.
  grep -qF '// opencode runtime config — do not edit by hand' "$WORK/opencode.jsonc"
  grep -qF '".opencode/plugins/on-hooks.ts"' "$WORK/opencode.jsonc"
  refute grep -qF '"opencode-codebase-index"' "$WORK/opencode.jsonc"
  # Valid JSON after removal.
  run python3 -c "
import json, sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
d = load_jsonc('${WORK}/opencode.jsonc')
assert 'opencode-codebase-index' not in d['plugin']
assert '.opencode/plugins/on-hooks.ts' in d['plugin']
print('VALID')
"
  assert_success
  assert_output "VALID"
}

@test "removing the only entry leaves an empty plugin array" {
  cat > "$WORK/opencode.jsonc" <<'JSONC_EOF'
{
  "plugin": ["opencode-codebase-index"]
}
JSONC_EOF

  run python3 "$TOOL" "$WORK/opencode.jsonc" "opencode-codebase-index"
  assert_success

  run python3 -c "
import json, sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
d = load_jsonc('${WORK}/opencode.jsonc')
assert d.get('plugin') == [] or 'plugin' not in d, d
print('VALID')
"
  assert_success
  assert_output "VALID"
}

@test "nested 'plugin' object key does not shadow the top-level plugin array" {
  # A module config (mcp block, env, etc.) may contain a nested "plugin" key on
  # its own line; the finder must anchor at depth 0 and remove from the REAL
  # top-level array only (review F2).
  cat > "$WORK/opencode.jsonc" <<'JSONC_EOF'
{
  "mcp": {
    "qmd": { "type": "local", "command": ["qmd"], "plugin": { "nested": true } }
  },
  "plugin": ["opencode-codebase-index", ".opencode/plugins/on-hooks.ts"]
}
JSONC_EOF

  run python3 "$TOOL" "$WORK/opencode.jsonc" "opencode-codebase-index"
  assert_success

  run python3 -c "
import json, sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
d = load_jsonc('${WORK}/opencode.jsonc')
assert 'opencode-codebase-index' not in d['plugin'], d['plugin']
assert '.opencode/plugins/on-hooks.ts' in d['plugin'], d['plugin']
assert d['mcp']['qmd']['plugin'] == {'nested': True}, d  # nested untouched
print('VALID')
"
  assert_success
  assert_output "VALID"
}

@test "compact single-line config (plugin key not at line start) is handled" {
  printf '{"mcp":{"plugin":{"x":1}},"plugin":["opencode-codebase-index","keep"]}' \
    > "$WORK/opencode.jsonc"

  run python3 "$TOOL" "$WORK/opencode.jsonc" "opencode-codebase-index"
  assert_success

  run python3 -c "
import json, sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
d = load_jsonc('${WORK}/opencode.jsonc')
assert 'opencode-codebase-index' not in d['plugin'], d
assert d['plugin'] == ['keep'], d
assert d['mcp']['plugin'] == {'x': 1}, d
print('VALID')
"
  assert_success
  assert_output "VALID"
}
