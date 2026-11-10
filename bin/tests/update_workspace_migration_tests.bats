#!/usr/bin/env bats
# =============================================================================
# bin/tests/update_workspace_migration_tests.bats
# bin/update.sh must fold the flat workspace keys into the `workspace` block
# before the reconciler runs: the reconciler drops any runtime key the dist no
# longer carries and copies the dist default, so migrating afterwards would
# silently replace the machine's global intent.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  UPDATE_SH="${REPO_ROOT}/bin/update.sh"
}

@test "update.sh migrates the workspace keys before the reconciler runs" {
  local migrate reconcile
  migrate="$(grep -n '_migrate_workspace_config "\$(_devbot_global_config)"' "${UPDATE_SH}" | cut -d: -f1 | head -1)"
  reconcile="$(grep -n '^    _reconcile_global_config$' "${UPDATE_SH}" | cut -d: -f1)"

  [ -n "${migrate}" ] && [ -n "${reconcile}" ]
  [ "${migrate}" -lt "${reconcile}" ]
}

@test "the reconciler runs only when both migrations are clean" {
  grep -q '_migrate_workflow_config && _migrate_workspace_config' "${UPDATE_SH}"
}
