#!/usr/bin/env bats
# =============================================================================
# bin/tests/update_workflow_migration_tests.bats
# The 1.9.0 versioned migration at its update call site: crossing 1.9.0 turns a
# project's `worktrees` key into `workflow`, and a migration that needs
# attention stops the reconciler and keeps the recorded version.
# =============================================================================

load update_helpers

setup_file() { _update_file_setup; }
setup() { _update_setup; }
teardown() { _update_teardown; }

@test "update migrates a registered project's worktrees key across 1.9.0" {
  _new_sandbox "1.8.0"
  local pkg="${SANDBOX}/pkg"
  mkdir -p "${pkg}"
  printf '{\n  "worktrees": false,\n  "devbot_dir": ".agents"\n}\n' > "${pkg}/.devbot.project.jsonc"
  cat > "${INSTALL}/.devbot.global.jsonc" <<JSONC_EOF
{
  "version": "1.8.0",
  "projects": ["${pkg}"]
}
JSONC_EOF
  _publish_release "g.txt" "release 1.9.0" "1.9.0"

  export DEVBOT_SKIP_GPU_DETECT=1
  _run_update

  [ "${UPDATE_STATUS}" -eq 0 ]
  [[ "${UPDATE_OUTPUT}" == *"MIGRATED"* ]]

  run cat "${pkg}/.devbot.project.jsonc"
  assert_output --partial '"workflow": "trunk"'
  refute_output --partial '"worktrees":'
}

@test "a migration that needs attention skips the reconciler and the version record" {
  _new_sandbox "1.8.0"
  cat > "${INSTALL}/.devbot.global.dist.jsonc" <<'JSONC_EOF'
{
  "version": "",
  "workflow": "worktrees",
  "dist_only": true
}
JSONC_EOF
  cat > "${INSTALL}/.devbot.global.jsonc" <<'JSONC_EOF'
{
  "version": "1.8.0",
  "worktrees": false,
  "workflow": "trunk"
}
JSONC_EOF
  _publish_release "g.txt" "release 1.9.0" "1.9.0"

  export DEVBOT_SKIP_GPU_DETECT=1
  _run_update

  [[ "${UPDATE_OUTPUT}" == *"config migrations need attention"* ]]

  # The reconciler must not remove the marker the user still has to resolve...
  run cat "${INSTALL}/.devbot.global.jsonc"
  assert_output --partial '"worktrees": false'
  # ...nor copy the dist default over the explicit workflow.
  refute_output --partial '"dist_only"'
  assert_output --partial '"workflow": "trunk"'
  # The old version survives, so the same range is retried next run.
  assert_output --partial '"version": "1.8.0"'
}

@test "update.sh migrates before the global reconciler runs" {
  local migrate reconcile
  migrate="$(grep -n 'if _migration_run_phase ' "${REPO_ROOT}/bin/update.sh" | cut -d: -f1 | head -1)"
  reconcile="$(grep -n '^    _reconcile_global_config$' "${REPO_ROOT}/bin/update.sh" | cut -d: -f1 | head -1)"

  [ -n "${migrate}" ] && [ -n "${reconcile}" ]
  [ "${migrate}" -lt "${reconcile}" ]

  grep -q 'migration_up-1.9.0' "${REPO_ROOT}/src/_shared/migrations.sh"
  grep -q 'migration_down-1.9.0' "${REPO_ROOT}/src/_shared/migrations.sh"
}
