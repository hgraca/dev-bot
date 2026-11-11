#!/usr/bin/env bats
# =============================================================================
# src/tools/devbot-cli/tests/bootstrap_tests.bats
# The one-release bootstrap: a 1.14.0 install gets the 1.15.0 config migration
# from the new module, while a newer install is left alone.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  SANDBOX="$(mktemp -d)"
  mkdir -p "${SANDBOX}/src/_shared"
  cp "${REPO_ROOT}/src/_shared/migrations.sh" \
    "${REPO_ROOT}/src/_shared/read_jsonc.py" \
    "${REPO_ROOT}/src/_shared/functions.sh" \
    "${REPO_ROOT}/src/_shared/migrate_workflow_config.py" \
    "${REPO_ROOT}/src/_shared/migrate_workspace_config.py" \
    "${SANDBOX}/src/_shared/"

  DEV_BOT_ROOT="${SANDBOX}"
  export DEV_BOT_ROOT
  printf '{\n  "version": "1.14.0",\n  "commit_memory": true,\n  "workflow": "trunk",\n  "monorepo": true\n}\n' \
    > "${SANDBOX}/.devbot.global.jsonc"

  # shellcheck source=../update.sh
  source "${REPO_ROOT}/src/tools/devbot-cli/update.sh"
}

teardown() {
  rm -rf "${SANDBOX}"
}

@test "bootstrap migrates a pre-1.15.0 config" {
  run _bootstrap_config_migrations
  assert_success

  run python3 "${SANDBOX}/src/_shared/read_jsonc.py" "${SANDBOX}/.devbot.global.jsonc" workspace workflow
  assert_output "trunk"
  run python3 "${SANDBOX}/src/_shared/read_jsonc.py" "${SANDBOX}/.devbot.global.jsonc" workspace type
  assert_output "polyrepo"
  [ ! -e "${SANDBOX}/storage/run/migrate-bootstrap-pending" ]
}

@test "a bootstrap that needs attention leaves a retry marker" {
  printf '{\n  "version": "1.14.0",\n  "workspace": { "commit_memory": false },\n  "commit_memory": true\n}\n' \
    > "${SANDBOX}/.devbot.global.jsonc"

  run _bootstrap_config_migrations
  assert_failure
  [ -f "${SANDBOX}/storage/run/migrate-bootstrap-pending" ]

  # The ambiguous config is left for the user to resolve.
  run cat "${SANDBOX}/.devbot.global.jsonc"
  assert_output --partial '"commit_memory": true'
  refute_output --partial '"type"'
}

@test "bootstrap is a no-op on a 1.15.0+ install" {
  printf '{\n  "version": "1.16.0",\n  "workspace": { "workflow": "trunk" }\n}\n' \
    > "${SANDBOX}/.devbot.global.jsonc"

  run _bootstrap_config_migrations
  assert_success

  run python3 "${SANDBOX}/src/_shared/read_jsonc.py" "${SANDBOX}/.devbot.global.jsonc" workspace workflow
  assert_output "trunk"
}
