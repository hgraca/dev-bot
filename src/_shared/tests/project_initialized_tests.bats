#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/project_initialized_tests.bats
#
# `devbot init` decides between "wire from scratch" and "reset then wire" on
# this helper. The project config is the witness, not `.devbot.project.sha`:
# every init/reinit clears the .sha first, so an interrupted run would read as
# "never initialised" and skip the reset path.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SANDBOX="$(mktemp -d)"

  # The helper verbatim, so the test cannot drift from production behaviour.
  awk '/^_devbot_project_initialized\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh" \
    > "${SANDBOX}/helper.sh"
  # shellcheck source=/dev/null
  source "${SANDBOX}/helper.sh"
}

teardown() {
  rm -rf "${SANDBOX}" 2>/dev/null || true
}

@test "a directory without a project config is not initialised" {
  run _devbot_project_initialized "${SANDBOX}"

  assert_failure
}

@test "a directory with a project config is initialised" {
  printf '{}\n' > "${SANDBOX}/.devbot.project.jsonc"

  run _devbot_project_initialized "${SANDBOX}"

  assert_success
}

@test "an existing wiring baseline alone is not enough" {
  printf 'abc123\n' > "${SANDBOX}/.devbot.project.sha"

  run _devbot_project_initialized "${SANDBOX}"

  assert_failure
}

@test "the project directory defaults to the current directory" {
  cd "${SANDBOX}" || return 1

  run _devbot_project_initialized
  assert_failure

  printf '{}\n' > "${SANDBOX}/.devbot.project.jsonc"
  run _devbot_project_initialized
  assert_success
}
