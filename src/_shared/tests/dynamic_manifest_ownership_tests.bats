#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/dynamic_manifest_ownership_tests.bats
# Tests for _devbot_manifest_owner_disabled — the predicate both harness
# inits use to skip a dynamic runtime manifest whose owning module is
# disabled, and both harness resets use to prune one.
#
# A module init emits .opencode/<name>.mcp.json (opencode) or
# .claude/<name>.mcp.json (claudecode) for values only known at init time
# (jetbrains' detected IDE port), per ADR harness-agnostic-module-init. A
# module owning several servers prefixes them with its name:
# <name>-<detail>.mcp.json (datasources).
#
# Ownership is exact-or-hyphen-prefixed: "<name>.mcp.json" and
# "<name>-<detail>.mcp.json" belong to <name>. A name that merely shares a
# prefix without the hyphen ("tools" vs "toolsx.mcp.json") is NOT a match.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"

  source "${PROJECT_ROOT}/src/_shared/functions.sh"
}

@test "exact name: a disabled module owns <name>.mcp.json" {
  run _devbot_manifest_owner_disabled "jetbrains.mcp.json" "jetbrains"
  assert_success
}

@test "prefixed name: a disabled module owns <name>-<detail>.mcp.json" {
  run _devbot_manifest_owner_disabled "datasources-mariadb-dev.mcp.json" "datasources"
  assert_success
}

@test "match on a later entry of the disabled set" {
  run _devbot_manifest_owner_disabled "jetbrains.mcp.json" $'mdctx\njetbrains'
  assert_success
}

@test "an enabled owner is not matched" {
  run _devbot_manifest_owner_disabled "jetbrains.mcp.json" $'mdctx\ngraphify'
  assert_failure
}

@test "a prefix without the - boundary is not a match" {
  run _devbot_manifest_owner_disabled "toolsx.mcp.json" "tools"
  assert_failure
}

@test "an empty disabled set matches nothing" {
  run _devbot_manifest_owner_disabled "jetbrains.mcp.json" ""
  assert_failure
}

@test "a non-manifest basename is never matched" {
  run _devbot_manifest_owner_disabled "jetbrains.json" "jetbrains"
  assert_failure
}
