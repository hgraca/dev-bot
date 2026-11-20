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

@test "a pending migration is retried when already on the target tag" {
  # A migration that failed on an earlier run leaves the recorded version behind.
  # The "already on the latest version" path used to exit before migrations ran,
  # so "run devbot update again" could never retry it.
  _new_sandbox "1.14.0:1.15.0"
  local pkg="${SANDBOX}/pkg"
  mkdir -p "${pkg}"
  cat > "${pkg}/.devbot.project.jsonc" <<'JSONC'
{
  "commit_memory": true,
  "workflow": "trunk"
}
JSONC
  cat > "${INSTALL}/.devbot.global.jsonc" <<JSONC_EOF
{
  "version": "1.14.0",
  "projects": ["${pkg}"]
}
JSONC_EOF

  export DEVBOT_SKIP_GPU_DETECT=1
  _run_update

  [ "${UPDATE_STATUS}" -eq 0 ]
  run cat "${pkg}/.devbot.project.jsonc"
  assert_output --partial '"workspace"'
}

# ── The dev line: ahead of the newest tag ────────────────────────────────────
# A checkout past the newest release never crosses a release, so the "ahead"
# path returned before any migration ran. The 1.19.0 guard migration is the one
# that bites: the tree promises a kubectl guard that no runtime config has.

@test "an ahead checkout applies the migration for the release it sits past" {
  _new_sandbox "1.15.0"
  local pkg="${SANDBOX}/pkg"
  mkdir -p "${pkg}"
  cat > "${pkg}/.devbot.project.jsonc" <<'JSONC'
{
  "commit_memory": true,
  "workflow": "trunk"
}
JSONC
  cat > "${INSTALL}/.devbot.global.jsonc" <<JSONC_EOF
{
  "version": "1.14.0",
  "projects": ["${pkg}"]
}
JSONC_EOF

  # One commit past the newest tag: `_head_vs_tag` reads `ahead`, not `at`.
  git -C "${INSTALL}" checkout -q main
  printf 'dev\n' > "${INSTALL}/dev.txt"
  git -C "${INSTALL}" add dev.txt
  git -C "${INSTALL}" commit -qm "dev commit after 1.15.0"

  export DEVBOT_SKIP_GPU_DETECT=1
  _run_update

  [ "${UPDATE_STATUS}" -eq 0 ]
  run cat "${pkg}/.devbot.project.jsonc"
  assert_output --partial '"workspace"'
}

@test "an unrecorded version is treated as pending, not as nothing to do" {
  # The field is empty on every checkout that is not exactly on a tag, so
  # "empty" cannot mean "up to date" — the migrations would never run at all.
  _new_sandbox "1.15.0"
  local pkg="${SANDBOX}/pkg"
  mkdir -p "${pkg}"
  cat > "${pkg}/.devbot.project.jsonc" <<'JSONC'
{
  "commit_memory": true,
  "workflow": "trunk"
}
JSONC
  cat > "${INSTALL}/.devbot.global.jsonc" <<JSONC_EOF
{
  "projects": ["${pkg}"]
}
JSONC_EOF

  git -C "${INSTALL}" checkout -q main
  printf 'dev\n' > "${INSTALL}/dev.txt"
  git -C "${INSTALL}" add dev.txt
  git -C "${INSTALL}" commit -qm "dev commit after 1.15.0"

  export DEVBOT_SKIP_GPU_DETECT=1
  _run_update

  [ "${UPDATE_STATUS}" -eq 0 ]
  run cat "${pkg}/.devbot.project.jsonc"
  assert_output --partial '"workspace"'
  # Applying them records where the machine now stands, so the next run is a
  # no-op rather than a full-range replay.
  run cat "${INSTALL}/.devbot.global.jsonc"
  assert_output --partial '"version": "1.15.0"'
}

@test "an ahead checkout seeds the 1.19.0 guard rules into the project" {
  # The defect the audit found: a dev-line machine never ran any migration, so a
  # module memory file promised a guard that no runtime config had. This drives
  # the real 1.19.0 up-half through the ahead path.
  _new_sandbox "1.19.0"
  local pkg="${SANDBOX}/pkg"
  mkdir -p "${pkg}"
  cat > "${pkg}/.devbot.project.jsonc" <<'JSONC'
{
  "project_name": "demo",
  "guards": [
    { "regex": "rm -rf", "message": "rm -rf is blocked" }
  ]
}
JSONC
  cat > "${INSTALL}/.devbot.global.jsonc" <<JSONC_EOF
{
  "version": "1.18.0",
  "projects": ["${pkg}"]
}
JSONC_EOF

  git -C "${INSTALL}" checkout -q main
  printf 'dev\n' > "${INSTALL}/dev.txt"
  git -C "${INSTALL}" add dev.txt
  git -C "${INSTALL}" commit -qm "dev commit after 1.19.0"

  export DEVBOT_SKIP_GPU_DETECT=1
  _run_update

  [ "${UPDATE_STATUS}" -eq 0 ]
  run cat "${pkg}/.devbot.project.jsonc"
  assert_output --partial 'kubectl'
  assert_output --partial 'kctl'
}
