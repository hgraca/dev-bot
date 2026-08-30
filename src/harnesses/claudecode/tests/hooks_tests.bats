#!/usr/bin/env bats
# =============================================================================
# src/harnesses/claudecode/tests/hooks_tests.bats
# Structural tests for the claudecode harness's hooks.json manifest.
#
# Guards two regressions that have bitten this file before:
#   1. An invalid hook event key (e.g. "Startup") — Claude Code skips the
#      entire settings.local.json file when any key is unrecognised.
#   2. A command path pointing into the dev-bot repo (src/harnesses/...) —
#      which does not resolve from an external project's cwd.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  HOOKS_JSON="$MODULE_DIR/hooks.json"

  command -v python3 &>/dev/null || skip "python3 not installed"
}

@test "hooks.json is valid JSON" {
  run python3 -c "import json,sys; json.load(open('$HOOKS_JSON'))"
  assert_success
}

@test "all hook event keys are valid Claude Code hook events" {
  run python3 -c "
import json
VALID = {'PreToolUse', 'PostToolUse', 'PostToolUseFailure', 'UserPromptSubmit',
         'Stop', 'SubagentStop', 'PreCompact', 'Notification',
         'SessionStart', 'SessionEnd'}
data = json.load(open('$HOOKS_JSON'))
invalid = sorted(set(data) - VALID)
if invalid:
    print('invalid event keys: ' + ', '.join(invalid))
    sys.exit(1)
"
  assert_success
}

@test "session start hook uses SessionStart (not Startup)" {
  run python3 -c "
import json
data = json.load(open('$HOOKS_JSON'))
assert 'SessionStart' in data, 'SessionStart key missing'
assert 'Startup' not in data, 'invalid Startup key present'
"
  assert_success
}

@test "every command path is project-relative (resolves from any project cwd)" {
  run python3 -c "
import json, sys
data = json.load(open('$HOOKS_JSON'))
bad = []
for event, entries in data.items():
    for entry in entries:
        for hook in entry.get('hooks', []):
            cmd = hook.get('command', '')
            if 'src/harnesses/' in cmd or cmd.startswith('/'):
                bad.append(cmd)
if bad:
    print('non-project-relative commands:')
    for c in bad:
        print('  ' + c)
    sys.exit(1)
"
  assert_success
}

@test "every command references a script under .claude/plugins/" {
  run python3 -c "
import json, sys
data = json.load(open('$HOOKS_JSON'))
for event, entries in data.items():
    for entry in entries:
        for hook in entry.get('hooks', []):
            cmd = hook.get('command', '')
            if '.claude/plugins/' not in cmd:
                print(f'{event}: command does not reference .claude/plugins/: {cmd}')
                sys.exit(1)
"
  assert_success
}

@test "the referenced plugin scripts exist on disk" {
  run python3 -c "
import json, os, sys
data = json.load(open('$HOOKS_JSON'))
hooks_dir = os.path.join('$MODULE_DIR', 'hooks')
for event, entries in data.items():
    for entry in entries:
        for hook in entry.get('hooks', []):
            cmd = hook.get('command', '')
            # Find the .claude/plugins/<name> token and map it to the real
            # script under src/harnesses/claudecode/hooks/.
            name = next((t.split('/')[-1] for t in cmd.split()
                         if '.claude/plugins/' in t), None)
            if name is None or not os.path.isfile(os.path.join(hooks_dir, name)):
                print(f'{event}: missing script {name or cmd}')
                sys.exit(1)
"
  assert_success
}
