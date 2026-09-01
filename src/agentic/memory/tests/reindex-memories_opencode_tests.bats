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
assert len(hooks) == 3, hooks
events = [h['event'] for h in hooks]
assert events.count('file.edited') == 2, events
assert events.count('file.deleted') == 1, events
assert 'reindex-memories.mcp.sh' in hooks[0]['run'][1], hooks
assert 'reindex-passive-memories.sh' in hooks[1]['run'][1], hooks
assert 'reindex-memories.mcp.sh' in hooks[2]['run'][1], hooks
print('MANIFEST:OK')
"
  assert_success
  grep -qF 'MANIFEST:OK' <<< "$output" || fail "manifest missing or malformed"
}

@test "hooks.json file.deleted hook matches latent memory paths (audit-28 NOTE-8)" {
  run python3 -c "
import json, re
data = json.load(open('${MODULE_DIR}/hooks.json'))
delete_hook = next(h for h in data['hooks'] if h['event'] == 'file.deleted')
pattern = delete_hook['match']['file']
assert re.search(pattern, '.agents/memory/latent/learnings/gone.md'), pattern
assert re.search(pattern, '.agents/memory/latent/global/k8s/note.md'), pattern
assert not re.search(pattern, '.agents/memory/active/note.md'), pattern
assert 'reindex-memories.mcp.sh' in delete_hook['run'][1], delete_hook
print('DELETE-HOOK:OK')
"
  assert_success
  grep -qF 'DELETE-HOOK:OK' <<< "$output" || fail "delete hook missing or misconfigured"
}

@test "shared reindex tools exist" {
  [ -f "$MODULE_DIR/tools/reindex-memories/reindex-memories.mcp.sh" ]
  [ -f "$MODULE_DIR/tools/reindex-passive-memories.sh" ]
}
