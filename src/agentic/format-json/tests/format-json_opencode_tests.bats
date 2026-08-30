#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  MODULE_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FIXTURES="$BATS_TEST_TMPDIR"
}

# ── hook declaration (manifest) ──────────────────────────────────────────────

@test "hooks.json declares file.edited hook for .json/.jsonc files" {
  run python3 -c "
import json
data = json.load(open('${MODULE_DIR}/hooks.json'))
hook = data['hooks'][0]
assert hook['event'] == 'file.edited', hook
assert 'json' in hook['match']['file'], hook
assert 'format-json.py' in hook['run'][1], hook
print('MANIFEST:OK')
"
  assert_success
  grep -qF 'MANIFEST:OK' <<< "$output" || fail "manifest missing or malformed"

  # Verify the format-json tool exists and can be called directly
  local test_json
  test_json="$(mktemp "$FIXTURES/tmp.XXXXXX.json")"
  printf '{"a":1,"b":2}\n' > "$test_json"

  run bash "${MODULE_DIR}/tools/format-json.mcp.sh" "$test_json"
  assert_success

  rm -f "$test_json"
}

# ── audit-25 FAIL-1: formatter reports must not trip the session alert ───────

@test "hooks.json routes report output to a dedicated format-json.log" {
  run python3 -c "
import json
data = json.load(open('${MODULE_DIR}/hooks.json'))
hook = data['hooks'][0]
log = hook.get('log', '')
assert log == '.agents/logs/format-json.log', log
print('LOG:OK')
"
  assert_success
  grep -qF 'LOG:OK' <<< "$output" || fail "manifest missing dedicated log field"
}
