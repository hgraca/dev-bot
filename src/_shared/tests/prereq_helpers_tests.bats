#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/prereq_helpers_tests.bats
# The module-prerequisite classification contract (see the PDR on prerequisite
# reporting):
#   - a prereq the module provisions via install.sh/update.sh -> NOTICE, continue
#   - a manual prereq the machine must provide -> ERROR, stop (non-zero)
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  source "${PROJECT_ROOT}/src/_shared/functions.sh"
}

@test "module-installed helper: present tool reports ok" {
  run _prereq_module_installed bash "bash"
  assert_success
  assert_output --partial "bash"
  refute_output --partial "NOTICE"
}

@test "module-installed helper: missing tool is a notice and returns 0" {
  run _prereq_module_installed definitely-not-a-real-tool-xyz "xyz"
  assert_success
  assert_output --partial "NOTICE"
  assert_output --partial "will install it"
}

@test "manual helper: present tool reports ok" {
  run _prereq_manual bash "bash"
  assert_success
  assert_output --partial "bash"
  refute_output --partial "ERROR"
}

@test "manual helper: missing tool errors and returns non-zero" {
  run _prereq_manual definitely-not-a-real-tool-xyz "xyz"
  assert_failure
  assert_output --partial "ERROR"
  assert_output --partial "install it manually"
}
