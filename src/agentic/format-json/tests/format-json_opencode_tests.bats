#!/usr/bin/env bats

setup() {
  load "$(npm root -g)/bats-support/load.bash"
  load "$(npm root -g)/bats-assert/load.bash"

  MODULE_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FIXTURES="$BATS_TEST_TMPDIR"
}

@test "opencode hook: exports OnFileEditedFormatJson (plugin loads)" {
  run bun -e "
    import { OnFileEditedFormatJson } from '${MODULE_DIR}/hooks/opencode/on-file_edited-format-json.ts';
    const plugin = await OnFileEditedFormatJson({ project: { worktree: '${MODULE_DIR}' } });
    const handler = plugin['event'];
    if (typeof handler === 'function') {
      console.log('PLUGIN:LOADED');
    }
  "
  assert_success
  grep -qF 'PLUGIN:LOADED' <<< "$output" || fail "plugin did not load"

  # Verify the format-json tool exists and can be called directly
  local test_json
  test_json="$(mktemp "$FIXTURES/tmp.XXXXXX.json")"
  printf '{"a":1,"b":2}\n' > "$test_json"

  run bash "${MODULE_DIR}/tools/format-json.sh" "$test_json"
  assert_success

  rm -f "$test_json"
}
