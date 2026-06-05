#!/usr/bin/env bats

setup() {
  load "$(npm root -g)/bats-support/load.bash"
  load "$(npm root -g)/bats-assert/load.bash"

  MODULE_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FIXTURES="$BATS_TEST_TMPDIR"
}

# ── opencode hook: file.edited on .md files ──────────────────────────────────

@test "opencode hook: triggers on .md file edited event (tool exists)" {
  run bun -e "
    import { OnFileEditedFormatMd } from '${MODULE_DIR}/hooks/opencode/on-file_edited-format-md.ts';
    const plugin = await OnFileEditedFormatMd({ project: { worktree: '${MODULE_DIR}' } });
    const handler = plugin['event'];
    if (typeof handler === 'function') {
      console.log('PLUGIN:LOADED');
    }
  "
  assert_success
  grep -qF 'PLUGIN:LOADED' <<< "$output" || fail "plugin did not load"

  # Verify the format-md tool exists and can be called directly
  local test_md
  test_md="$(mktemp "$FIXTURES/tmp.XXXXXX.md")"
  echo "| a | b |" > "$test_md"
  echo "|---|---|" >> "$test_md"
  echo "| 1 | 2 |" >> "$test_md"

  run bash "${MODULE_DIR}/tools/format-md.sh" "$test_md"
  assert_success

  rm -f "$test_md"
}
