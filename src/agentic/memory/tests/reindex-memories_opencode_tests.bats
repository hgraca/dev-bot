#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  MODULE_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FIXTURES="$BATS_TEST_TMPDIR"
}

@test "hooks.json declares reindex-memories file.edited + session.created hooks" {
  run python3 -c "
import json
data = json.load(open('${MODULE_DIR}/hooks.json'))
hooks = data['hooks']
assert len(hooks) == 3, hooks
events = [h['event'] for h in hooks]
assert events.count('file.edited') == 2, events
assert events.count('session.created') == 1, events
assert 'reindex-memories.mcp.sh' in hooks[0]['run'][1], hooks
assert 'reindex-passive-memories.sh' in hooks[1]['run'][1], hooks
assert 'reindex-memories.mcp.sh' in hooks[2]['run'][1], hooks
print('MANIFEST:OK')
"
  assert_success
  grep -qF 'MANIFEST:OK' <<< "$output" || fail "manifest missing or malformed"
}

@test "hooks.json session.created prune hook matches latent memory paths (audit-31 §5)" {
  # audit-31 §5: the file.deleted hook was dead code under both harnesses (no
  # delete events for external bash rm) — dropped in favor of a session-start
  # prune (32be1e82). Assert the surviving session.created prune hook's shape.
  run python3 -c "
import json, re
data = json.load(open('${MODULE_DIR}/hooks.json'))
prune_hook = next(h for h in data['hooks'] if h['event'] == 'session.created')
assert prune_hook['id'] == 'reindex-memories-prune-start', prune_hook
assert prune_hook['run'][-1] == 'prune', prune_hook
assert 'reindex-memories.mcp.sh' in prune_hook['run'][1], prune_hook
assert prune_hook['log'] == '.agents/logs/qmd-index.log', prune_hook
assert 'file.deleted' not in [h['event'] for h in data['hooks']], data['hooks']
print('PRUNE-START:OK')
"
  assert_success
  grep -qF 'PRUNE-START:OK' <<< "$output" || fail "prune-start hook missing or misconfigured"
}

@test "shared reindex tools exist" {
  [ -f "$MODULE_DIR/tools/reindex-memories/reindex-memories.mcp.sh" ]
  [ -f "$MODULE_DIR/tools/reindex-passive-memories.sh" ]
}
