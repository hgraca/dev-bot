#!/usr/bin/env bats

setup() {
  load "$(npm root -g)/bats-support/load.bash"
  load "$(npm root -g)/bats-assert/load.bash"

  MODULE_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FIXTURES="$BATS_TEST_TMPDIR"
}

@test "opencode hook: exports OnFileEditedFormatYml (plugin loads)" {
  run bun -e "
    import { OnFileEditedFormatYml } from '${MODULE_DIR}/hooks/opencode/on-file_edited-format-yml.ts';
    const plugin = await OnFileEditedFormatYml({ project: { worktree: '${MODULE_DIR}' } });
    const handler = plugin['event'];
    if (typeof handler === 'function') {
      console.log('PLUGIN:LOADED');
    }
  "
  assert_success
  grep -qF 'PLUGIN:LOADED' <<< "$output" || fail "plugin did not load"

  # Verify the format-yml tool exists and can be called directly
  local test_yml
  test_yml="$(mktemp "$FIXTURES/tmp.XXXXXX.yml")"
  printf 'a: 1\nb: 2\n' > "$test_yml"

  run bash "${MODULE_DIR}/tools/format-yml.sh" "$test_yml"
  assert_success

  rm -f "$test_yml"
}
