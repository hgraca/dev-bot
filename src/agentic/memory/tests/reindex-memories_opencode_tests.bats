#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  MODULE_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FIXTURES="$BATS_TEST_TMPDIR"
}

@test "hooks.json declares reindex-memories file.edited hooks" {
  run python3 -c "
import json
data = json.load(open('${MODULE_DIR}/hooks.json'))
hooks = data['hooks']
assert len(hooks) == 2, hooks
assert all(h['event'] == 'file.edited' for h in hooks), hooks
assert 'reindex-memories.mcp.sh' in hooks[0]['run'][1], hooks
assert 'reindex-passive-memories.sh' in hooks[1]['run'][1], hooks
print('MANIFEST:OK')
"
  assert_success
  grep -qF 'MANIFEST:OK' <<< "$output" || fail "manifest missing or malformed"
}

@test "shared reindex tools exist" {
  [ -f "$MODULE_DIR/tools/reindex-memories/reindex-memories.mcp.sh" ]
  [ -f "$MODULE_DIR/tools/reindex-passive-memories.sh" ]
}
