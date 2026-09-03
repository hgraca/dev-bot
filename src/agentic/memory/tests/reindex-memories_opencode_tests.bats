#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  MODULE_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FIXTURES="$BATS_TEST_TMPDIR"
}

@test "hooks.json declares file.edited reindex hooks only (prune moved to start.sh)" {
  # audit-31 §5 / audit-36: the delete→prune self-heal no longer fires from a
  # session.created hook — it runs detached from the harness start scripts
  # (start.sh → _devbot_prune_memories_detached) so it fires per launch and
  # gets a head start ahead of the MCP fleet boot (audit-34 NOTE-8, audit-35
  # FAIL).
  run python3 -c "
import json
data = json.load(open('${MODULE_DIR}/hooks.json'))
hooks = data['hooks']
assert len(hooks) == 2, hooks
events = [h['event'] for h in hooks]
assert events.count('file.edited') == 2, events
assert 'session.created' not in events, events
assert 'reindex-memories.mcp.sh' in hooks[0]['run'][1], hooks
assert 'reindex-passive-memories.sh' in hooks[1]['run'][1], hooks
print('MANIFEST:OK')
"
  assert_success
  grep -qF 'MANIFEST:OK' <<< "$output" || fail "manifest missing or malformed"
}

@test "hooks.json no longer declares a session.created prune hook" {
  # audit-36: the session.created prune hook was removed from the manifest —
  # assert its absence so a future re-introduction (which would re-add boot
  # contention + first-session-only firing) is caught.
  run python3 -c "
import json
data = json.load(open('${MODULE_DIR}/hooks.json'))
assert not any(h['event'] == 'session.created' for h in data['hooks']), data['hooks']
print('NO-PRUNE-HOOK:OK')
"
  assert_success
  grep -qF 'NO-PRUNE-HOOK:OK' <<< "$output" || fail "session.created prune hook still present"
}

@test "shared reindex tools exist" {
  [ -f "$MODULE_DIR/tools/reindex-memories/reindex-memories.mcp.sh" ]
  [ -f "$MODULE_DIR/tools/reindex-passive-memories.sh" ]
}
