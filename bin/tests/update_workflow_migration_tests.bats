#!/usr/bin/env bats
# =============================================================================
# bin/tests/update_workflow_migration_tests.bats
# bin/update.sh's `worktrees` -> `workflow` migration at its call site: the
# sandbox install actually runs it, and a migration that needs attention stops
# the reconciler from overwriting the config.
# =============================================================================

load update_helpers

setup_file() { _update_file_setup; }
setup() { _update_setup; }
teardown() { _update_teardown; }

@test "update migrates a registered project's worktrees key" {
  _new_sandbox "1.0.0:1.1.0"
  local pkg="${SANDBOX}/pkg"
  mkdir -p "${pkg}"
  printf '{\n  "worktrees": false,\n  "devbot_dir": ".agents"\n}\n' > "${pkg}/.devbot.project.jsonc"
  cat > "${INSTALL}/.devbot.global.jsonc" <<JSONC_EOF
{
  "version": "",
  "projects": ["${pkg}"]
}
JSONC_EOF
  _publish_release "g.txt" "release 1.2.0" "1.2.0"

  export DEVBOT_SKIP_GPU_DETECT=1
  _run_update

  [ "${UPDATE_STATUS}" -eq 0 ]
  [[ "${UPDATE_OUTPUT}" == *"MIGRATED"* ]]

  run cat "${pkg}/.devbot.project.jsonc"
  assert_output --partial '"workflow": "trunk"'
  refute_output --partial '"worktrees":'
}

@test "update skips the reconciler when the migration needs attention" {
  _new_sandbox "1.0.0:1.1.0"
  cat > "${INSTALL}/.devbot.global.dist.jsonc" <<'JSONC_EOF'
{
  "version": "",
  "workflow": "worktrees",
  "dist_only": true
}
JSONC_EOF
  cat > "${INSTALL}/.devbot.global.jsonc" <<'JSONC_EOF'
{
  "version": "",
  "worktrees": false,
  "workflow": "trunk"
}
JSONC_EOF
  _publish_release "g.txt" "release 1.2.0" "1.2.0"

  export DEVBOT_SKIP_GPU_DETECT=1
  _run_update

  [[ "${UPDATE_OUTPUT}" == *"migration needs attention"* ]]
  [[ "${UPDATE_OUTPUT}" == *"reconciliation skipped"* ]]

  # The reconciler must not remove the marker the user still has to resolve...
  run cat "${INSTALL}/.devbot.global.jsonc"
  assert_output --partial '"worktrees": false'
  # ...nor copy the dist default over the explicit workflow.
  refute_output --partial '"dist_only"'
  assert_output --partial '"workflow": "trunk"'
}

@test "update.sh migrates the key before the global reconciler runs" {
  local migrate reconcile
  migrate="$(grep -n '^  if _migrate_workflow_config' "${REPO_ROOT}/bin/update.sh" | cut -d: -f1)"
  reconcile="$(grep -n '^    _reconcile_global_config$' "${REPO_ROOT}/bin/update.sh" | cut -d: -f1)"

  [ -n "${migrate}" ] && [ -n "${reconcile}" ]
  [ "${migrate}" -lt "${reconcile}" ]

  grep -q 'migrate_workflow_config.py' "${REPO_ROOT}/bin/update.sh"
}
