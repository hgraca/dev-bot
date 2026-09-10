#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/auto_update_tests.bats
# Tests for _devbot_auto_update_if_enabled — the bare-`devbot` start hook that
# runs `bin/update.sh --auto` when the global config's `auto_update` is not
# explicitly false. Failures are swallowed: a start must never be blocked.
#
# Run from project root:
#   bats src/_shared/tests/auto_update_tests.bats
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"

  export DEV_BOT_ROOT="$(mktemp -d)"
  mkdir -p "${DEV_BOT_ROOT}/bin"
  source "${PROJECT_ROOT}/src/_shared/functions.sh"
  CONFIG="${DEV_BOT_ROOT}/.devbot.global.jsonc"

  # Stub update.sh: records its args, exits with UPDATE_RC (default 0).
  cat > "${DEV_BOT_ROOT}/bin/update.sh" <<EOF
#!/usr/bin/env bash
echo "update-called \$*" >> "${DEV_BOT_ROOT}/update.log"
exit "\${UPDATE_RC:-0}"
EOF
  chmod +x "${DEV_BOT_ROOT}/bin/update.sh"
}

teardown() {
  unset DEV_BOT_ROOT UPDATE_RC
  rm -rf "${DEV_BOT_ROOT}" 2>/dev/null || true
}

@test "auto-update runs update.sh --auto when auto_update is absent (default true)" {
  printf '{\n  "harness": "opencode"\n}\n' > "${CONFIG}"
  run _devbot_auto_update_if_enabled
  assert_success
  run cat "${DEV_BOT_ROOT}/update.log"
  assert_output "update-called --auto"
}

@test "auto-update runs when auto_update is true" {
  printf '{\n  "auto_update": true\n}\n' > "${CONFIG}"
  run _devbot_auto_update_if_enabled
  assert_success
  [ -f "${DEV_BOT_ROOT}/update.log" ]
}

@test "auto-update is skipped when auto_update is false" {
  printf '{\n  "auto_update": false\n}\n' > "${CONFIG}"
  run _devbot_auto_update_if_enabled
  assert_success
  [ ! -e "${DEV_BOT_ROOT}/update.log" ]
}

@test "a failed auto-update warns and returns success (start continues)" {
  printf '{\n  "auto_update": true\n}\n' > "${CONFIG}"
  UPDATE_RC=1 run _devbot_auto_update_if_enabled
  assert_success
  assert_output --partial "auto-update failed"
  assert_output --partial "continuing on the current version"
}

@test "auto-update is a no-op when update.sh is absent" {
  printf '{\n  "auto_update": true\n}\n' > "${CONFIG}"
  rm -f "${DEV_BOT_ROOT}/bin/update.sh"
  run _devbot_auto_update_if_enabled
  assert_success
  [ ! -e "${DEV_BOT_ROOT}/update.log" ]
}
