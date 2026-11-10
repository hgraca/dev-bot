#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/migrate_workspace_config_tests.bats
# migrate_workspace_config.py — flat `commit_memory` / `workflow` / `monorepo`
# (and the older `worktrees`) move into the `workspace` block, without touching
# anything else in the file.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SCRIPT="${PROJECT_ROOT}/src/_shared/migrate_workspace_config.py"
  READER="${PROJECT_ROOT}/src/_shared/read_jsonc.py"
  SANDBOX="$(mktemp -d)"
  CONF="${SANDBOX}/.devbot.project.jsonc"

  command -v python3 &>/dev/null || skip "python3 not installed"
}

teardown() {
  rm -r "${SANDBOX}" 2>/dev/null || true
}

@test "the three flat keys become one workspace block" {
  cat > "${CONF}" <<'JSONC'
{
  "project_name": "demo",
  "commit_memory": true,
  "workflow": "trunk",
  "monorepo": true,
  "datasources": []
}
JSONC

  run python3 "${SCRIPT}" "${CONF}"
  assert_success
  assert_output --partial "MIGRATED"

  run cat "${CONF}"
  assert_output --partial '"type": "polyrepo"'
  assert_output --partial '"commit_memory": true'
  assert_output --partial '"workflow": "trunk"'
  refute_output --partial '"monorepo"'

  # The root keys are gone; the values live inside the block only.
  run python3 "${READER}" "${CONF}" commit_memory
  assert_output ""
  run python3 "${READER}" "${CONF}" workflow
  assert_output ""
  run python3 "${READER}" "${CONF}" workspace workflow
  assert_output "trunk"
}

@test "monorepo false becomes an explicit repo type" {
  # An explicit `false` must survive even when the global default is a
  # polyrepo, so it is written rather than dropped as "the default".
  printf '{\n  "project_name": "x",\n  "monorepo": false\n}\n' > "${CONF}"

  run python3 "${SCRIPT}" "${CONF}"
  assert_success

  run python3 "${READER}" "${CONF}" workspace type
  assert_output "repo"
}

@test "the retired worktrees boolean maps to the workflow name" {
  printf '{\n  "project_name": "x",\n  "worktrees": false\n}\n' > "${CONF}"

  run python3 "${SCRIPT}" "${CONF}"
  assert_success

  run python3 "${READER}" "${CONF}" workspace workflow
  assert_output "trunk"
}

@test "comments and nested objects survive untouched" {
  cat > "${CONF}" <<'JSONC'
{
  // project settings
  "project_name": "demo",
  "auto_recover": { "max_attempts": 5 }, // retry budget
  "commit_memory": false
}
JSONC

  run python3 "${SCRIPT}" "${CONF}"
  assert_success

  run cat "${CONF}"
  assert_output --partial "// project settings"
  assert_output --partial '"auto_recover": { "max_attempts": 5 }, // retry budget'
}

@test "a root key merges into an existing workspace block" {
  cat > "${CONF}" <<'JSONC'
{
  "a": 1,
  "workspace": {
    "type": "repo"
  },
  "commit_memory": true
}
JSONC

  run python3 "${SCRIPT}" "${CONF}"
  assert_success

  run python3 "${READER}" "${CONF}" workspace commit_memory
  assert_output "true"
  run python3 "${READER}" "${CONF}" workspace type
  assert_output "repo"
}

@test "a key present in both places is reported and left alone" {
  cat > "${CONF}" <<'JSONC'
{
  "workspace": {
    "type": "polyrepo"
  },
  "monorepo": true
}
JSONC
  cp "${CONF}" "${SANDBOX}/before"

  run python3 "${SCRIPT}" "${CONF}"
  assert_failure
  assert_output --partial "sets both a root key and workspace.type"

  run cmp -s "${CONF}" "${SANDBOX}/before"
  assert_success
}

@test "a second run changes nothing" {
  printf '{\n  "commit_memory": true,\n  "monorepo": true\n}\n' > "${CONF}"
  run python3 "${SCRIPT}" "${CONF}"
  assert_success
  cp "${CONF}" "${SANDBOX}/after-first"

  run python3 "${SCRIPT}" "${CONF}"
  assert_success
  [ -z "${output}" ]

  run cmp -s "${CONF}" "${SANDBOX}/after-first"
  assert_success
}

@test "a symlinked config is rewritten through to its target" {
  printf '{\n  "monorepo": true\n}\n' > "${SANDBOX}/real.jsonc"
  ln -s "real.jsonc" "${CONF}"

  run python3 "${SCRIPT}" "${CONF}"
  assert_success

  [ -L "${CONF}" ]
  run python3 "${READER}" "${SANDBOX}/real.jsonc" workspace type
  assert_output "polyrepo"
}

@test "an unparseable config is reported and left untouched" {
  printf '{\n  "commit_memory": true,,\n}\n' > "${CONF}"
  cp "${CONF}" "${SANDBOX}/before"

  run python3 "${SCRIPT}" "${CONF}"
  assert_failure
  assert_output --partial "cannot parse"

  run cmp -s "${CONF}" "${SANDBOX}/before"
  assert_success
}

@test "a config with no legacy key is not rewritten" {
  printf '{\n  "project_name": "x",\n  "workspace": { "type": "repo" }\n}\n' > "${CONF}"
  cp "${CONF}" "${SANDBOX}/before"

  run python3 "${SCRIPT}" "${CONF}"
  assert_success
  [ -z "${output}" ]

  run cmp -s "${CONF}" "${SANDBOX}/before"
  assert_success
}

@test "a root workflow and the retired worktrees key are reported, not merged" {
  printf '{\n  "workflow": "trunk",\n  "worktrees": true\n}\n' > "${CONF}"
  cp "${CONF}" "${SANDBOX}/before"

  run python3 "${SCRIPT}" "${CONF}"
  assert_failure
  assert_output --partial "sets both"

  run cmp -s "${CONF}" "${SANDBOX}/before"
  assert_success
}

@test "an unreadable config is reported instead of tracebacking" {
  skip "running as root — permissions are not enforced"
  [[ "$(id -u)" -ne 0 ]] || skip "running as root — permissions are not enforced"

  printf '{\n  "monorepo": true\n}\n' > "${CONF}"
  chmod 000 "${CONF}"

  run python3 "${SCRIPT}" "${CONF}"
  chmod 644 "${CONF}"

  assert_failure
  assert_output --partial "NEEDS_ATTENTION"
  refute_output --partial "Traceback"
}

@test "legacy keys need not be adjacent" {
  cat > "${CONF}" <<'JSONC'
{
  "commit_memory": true,
  "project_name": "demo",
  "workflow": "trunk",
  "datasources": []
}
JSONC

  run python3 "${SCRIPT}" "${CONF}"
  assert_success

  run python3 "${READER}" "${CONF}" workspace commit_memory
  assert_output "true"
  run python3 "${READER}" "${CONF}" workspace workflow
  assert_output "trunk"
  run python3 "${READER}" "${CONF}" project_name
  assert_output "demo"
}

@test "a malformed legacy boolean is reported and left untouched" {
  printf '{\n  "worktrees": "false"\n}\n' > "${CONF}"
  cp "${CONF}" "${SANDBOX}/before"

  run python3 "${SCRIPT}" "${CONF}"
  assert_failure
  assert_output --partial "unrecognised \"worktrees\" value"

  run cmp -s "${CONF}" "${SANDBOX}/before"
  assert_success
}

@test "a comment between a value and its comma is handled" {
  printf '{\n  "commit_memory": true // note\n  ,\n  "datasources": []\n}\n' > "${CONF}"

  run python3 "${SCRIPT}" "${CONF}"
  assert_success

  run cat "${CONF}"
  assert_output --partial '"commit_memory": true'
  refute_output --partial '"commit_memory": true,'
}

@test "monorepo false conflicts with a nested workspace type" {
  printf '{ "workspace": { "type": "polyrepo" }, "monorepo": false }\n' > "${CONF}"
  cp "${CONF}" "${SANDBOX}/before"

  run python3 "${SCRIPT}" "${CONF}"
  assert_failure
  assert_output --partial "sets both a root key and workspace.type"

  run cmp -s "${CONF}" "${SANDBOX}/before"
  assert_success
}

@test "a leading comment containing a brace is skipped" {
  printf '// example object: { ... }\n{\n  "monorepo": true\n}\n' > "${CONF}"

  run python3 "${SCRIPT}" "${CONF}"
  assert_success

  run cat "${CONF}"
  assert_output --partial '// example object: { ... }'
  assert_output --partial '"type": "polyrepo"'
}
