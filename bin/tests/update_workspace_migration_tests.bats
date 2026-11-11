#!/usr/bin/env bats
# =============================================================================
# bin/tests/update_workspace_migration_tests.bats
# The 1.15.0 versioned migration at its update call site: crossing 1.15.0 folds
# the flat workspace keys into the `workspace` block before the reconciler runs,
# so the reconciler cannot replace the machine's intent with a dist default.
# =============================================================================

load update_helpers

setup_file() { _update_file_setup; }
setup() { _update_setup; }
teardown() { _update_teardown; }

@test "update folds a registered project's flat keys into the workspace block" {
  _new_sandbox "1.14.0"
  local pkg="${SANDBOX}/pkg"
  mkdir -p "${pkg}"
  cat > "${pkg}/.devbot.project.jsonc" <<'JSONC'
{
  "commit_memory": true,
  "workflow": "trunk",
  "monorepo": true
}
JSONC
  cat > "${INSTALL}/.devbot.global.jsonc" <<JSONC_EOF
{
  "version": "1.14.0",
  "projects": ["${pkg}"]
}
JSONC_EOF
  _publish_release "g.txt" "release 1.15.0" "1.15.0"

  export DEVBOT_SKIP_GPU_DETECT=1
  _run_update

  [ "${UPDATE_STATUS}" -eq 0 ]
  [[ "${UPDATE_OUTPUT}" == *"MIGRATED"* ]]

  run cat "${pkg}/.devbot.project.jsonc"
  assert_output --partial '"workspace"'
  assert_output --partial '"type": "polyrepo"'
  assert_output --partial '"commit_memory": true'
  assert_output --partial '"workflow": "trunk"'
  refute_output --partial '"monorepo"'
}

@test "update.sh runs migrate before the reconciler and ships both 1.15.0 halves" {
  local migrate reconcile
  migrate="$(grep -n 'if _migration_run_phase ' "${REPO_ROOT}/bin/update.sh" | cut -d: -f1 | head -1)"
  reconcile="$(grep -n '^    _reconcile_global_config$' "${REPO_ROOT}/bin/update.sh" | cut -d: -f1 | head -1)"

  [ -n "${migrate}" ] && [ -n "${reconcile}" ]
  [ "${migrate}" -lt "${reconcile}" ]

  grep -q 'migration_up-1.15.0' "${REPO_ROOT}/src/_shared/migrations.sh"
  grep -q 'migration_down-1.15.0' "${REPO_ROOT}/src/_shared/migrations.sh"
}
