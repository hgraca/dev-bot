#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/devbot_root_tests.bats
# The DEV_BOT_ROOT fallback in src/_shared/functions.sh must resolve the
# repository root — the parent of src/ — so a script that sources the library
# without exporting DEV_BOT_ROOT still finds .devbot.global.jsonc and src/.
# The fallback previously climbed one level short (<repo>/src).
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"
}

@test "DEV_BOT_ROOT fallback resolves the repo root when the env var is unset" {
  run env -u DEV_BOT_ROOT bash -c \
    "source '$PROJECT_ROOT/src/_shared/functions.sh' && printf '%s' \"\$DEV_BOT_ROOT\""
  assert_success
  assert_output "$PROJECT_ROOT"
}

@test "DEV_BOT_ROOT fallback points at the dir holding .devbot.global.dist.jsonc" {
  run env -u DEV_BOT_ROOT bash -c \
    "source '$PROJECT_ROOT/src/_shared/functions.sh' && test -f \"\$DEV_BOT_ROOT/.devbot.global.dist.jsonc\""
  assert_success
}
