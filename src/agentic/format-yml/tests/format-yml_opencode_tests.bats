#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  MODULE_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FIXTURES="$BATS_TEST_TMPDIR"
}

# ── hook declaration (manifest) ──────────────────────────────────────────────

@test "hooks.json declares file.edited hook for .yml/.yaml files" {
  run python3 -c "
import json
data = json.load(open('${MODULE_DIR}/hooks.json'))
hook = data['hooks'][0]
assert hook['event'] == 'file.edited', hook
assert 'ya?ml' in hook['match']['file'], hook
assert 'format-yml.py' in hook['run'][1], hook
print('MANIFEST:OK')
"
  assert_success
  grep -qF 'MANIFEST:OK' <<< "$output" || fail "manifest missing or malformed"

  # Verify the format-yml tool exists and can be called directly
  local test_yml
  test_yml="$(mktemp "$FIXTURES/tmp.XXXXXX.yml")"
  printf 'a: 1\nb: 2\n' > "$test_yml"

  run bash "${MODULE_DIR}/tools/format-yml.mcp.sh" "$test_yml"
  assert_success

  rm -f "$test_yml"
}

# ── audit-25 FAIL-1: formatter reports must not trip the session alert ───────

@test "hooks.json routes report output to a dedicated format-yml.log" {
  run python3 -c "
import json
data = json.load(open('${MODULE_DIR}/hooks.json'))
hook = data['hooks'][0]
log = hook.get('log', '')
assert log == '.agents/logs/format-yml.log', log
print('LOG:OK')
"
  assert_success
  grep -qF 'LOG:OK' <<< "$output" || fail "manifest missing dedicated log field"
}
