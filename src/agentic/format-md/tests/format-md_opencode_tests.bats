#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  MODULE_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FIXTURES="$BATS_TEST_TMPDIR"
}

# ── hook declaration (manifest) ──────────────────────────────────────────────

@test "hooks.json declares file.edited hook for .md files" {
  run python3 -c "
import json
data = json.load(open('${MODULE_DIR}/hooks.json'))
hook = data['hooks'][0]
assert hook['event'] == 'file.edited', hook
assert '.md' in hook['match']['file'], hook
assert 'format-md.py' in hook['run'][1], hook
print('MANIFEST:OK')
"
  assert_success
  grep -qF 'MANIFEST:OK' <<< "$output" || fail "manifest missing or malformed"

  # Verify the format-md tool exists and can be called directly
  local test_md
  test_md="$(mktemp "$FIXTURES/tmp.XXXXXX.md")"
  echo "| a | b |" > "$test_md"
  echo "|---|---|" >> "$test_md"
  echo "| 1 | 2 |" >> "$test_md"

  run bash "${MODULE_DIR}/tools/format-md.mcp.sh" "$test_md"
  assert_success

  rm -f "$test_md"
}

# ── audit-25 FAIL-1: formatter reports must not trip the session alert ───────

@test "hooks.json routes report output to a dedicated format-md.log" {
  run python3 -c "
import json
data = json.load(open('${MODULE_DIR}/hooks.json'))
hook = data['hooks'][0]
log = hook.get('log', '')
assert log == '.agents/logs/format-md.log', log
print('LOG:OK')
"
  assert_success
  grep -qF 'LOG:OK' <<< "$output" || fail "manifest missing dedicated log field"
}
