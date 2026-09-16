#!/usr/bin/env bats
# =============================================================================
# src/harnesses/opencode/tests/dist_config_tests.bats
# Guards the opencode dist template. It is copied verbatim to opencode.jsonc on
# first init, and opencode hard-fails on invalid config — so a malformed comment
# or trailing comma in the template would break every fresh project.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../../.." && pwd)"
  DIST="${PROJECT_ROOT}/src/harnesses/opencode/opencode.dist.jsonc"
  READER="${PROJECT_ROOT}/src/_shared/read_jsonc.py"
}

@test "opencode.dist.jsonc parses as valid JSONC" {
  run python3 "$READER" "$DIST"
  assert_success
}

@test "opencode.dist.jsonc declares a schema-valid lsp field" {
  run python3 "$READER" "$DIST" lsp
  assert_success
  # opencode schema: boolean, or an object of per-server overrides.
  [[ "$output" == "true" || "$output" == "false" || "$output" == \{* ]]
}

@test "opencode.dist.jsonc plugin array carries the server plugins" {
  # opencode.json's plugin array is the *server* plugin surface: opencode
  # installs each npm spec at startup and caches it in ~/.cache/opencode.
  run python3 "$READER" "$DIST" plugin
  assert_success
  assert_output --partial '.opencode/plugins/on-hooks.ts'
  assert_output --partial '"opencode-pty"'
}

@test "opencode.dist.jsonc plugin array excludes TUI plugins" {
  # TUI plugins belong in tui.json. opencode.json's schema declares no "tui"
  # key and sets additionalProperties:false, so a TUI plugin listed here is
  # schema-invalid and opencode refuses to start.
  run python3 "$READER" "$DIST" plugin
  assert_success
  refute_output --partial 'opencode-tabs'
  refute_output --partial 'opencode-user-timeline'
  refute_output --partial 'opencode-dir-tree-tui'
  refute_output --partial 'opencode-better-sidebar'
  refute_output --partial 'opencode-worktree'
  refute_output --partial 'streetturtle'
}