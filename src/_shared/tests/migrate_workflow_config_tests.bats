#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/migrate_workflow_config_tests.bats
# The retired `worktrees` config key migration: the true/false mapping, comment
# preservation, idempotence, and the both-keys file.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  MODULE_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  TOOL="${MODULE_DIR}/migrate_workflow_config.py"

  WORK="${BATS_TEST_TMPDIR}/migrate"
  GLOBAL="${WORK}/global.jsonc"
  P1="${WORK}/p1"
  P2="${WORK}/p2"
  P3="${WORK}/p3"
  mkdir -p "${P1}" "${P2}" "${P3}"
}

@test "migrates the global config and every registered project" {
  cat > "${GLOBAL}" <<EOF
{
  "worktrees": true,
  "projects": ["${P1}", "${P2}", "${P3}"]
}
EOF

  printf '{ "worktrees": true }\n' > "${P1}/.devbot.project.jsonc"
  printf '{ "worktrees": false, "datasources": ["db"] }\n' > "${P2}/.devbot.project.jsonc"

  run python3 "${TOOL}" "${GLOBAL}"

  assert_success

  grep -q '"workflow": "worktrees"' "${GLOBAL}"
  ! grep -q '"worktrees":' "${GLOBAL}"

  grep -q '"workflow": "worktrees"' "${P1}/.devbot.project.jsonc"
  ! grep -q '"worktrees":' "${P1}/.devbot.project.jsonc"

  # false meant "opted out of worktrees", which is the trunk workflow now.
  grep -q '"workflow": "trunk"' "${P2}/.devbot.project.jsonc"
  grep -q '"datasources": \["db"\]' "${P2}/.devbot.project.jsonc"
  ! grep -q '"worktrees":' "${P2}/.devbot.project.jsonc"

  # A project without a config is untouched and none is created.
  [ ! -e "${P3}/.devbot.project.jsonc" ]
}

@test "preserves trailing comments and unrelated keys" {
  cat > "${GLOBAL}" <<EOF
{
  "projects": ["${P1}"]
}
EOF

  cat > "${P1}/.devbot.project.jsonc" <<'EOF'
{
  // keep this comment
  "worktrees": false, // the old flag
  "commit_memory": true
}
EOF

  run python3 "${TOOL}" "${GLOBAL}"

  assert_success
  assert_output --partial 'worktrees=false -> workflow=trunk'

  grep -q '// keep this comment' "${P1}/.devbot.project.jsonc"
  grep -q '"workflow": "trunk", // the old flag' "${P1}/.devbot.project.jsonc"
  grep -q '"commit_memory": true' "${P1}/.devbot.project.jsonc"
}

@test "is idempotent: a second run reports and changes nothing" {
  cat > "${GLOBAL}" <<EOF
{
  "projects": ["${P1}"]
}
EOF

  printf '{ "worktrees": true }\n' > "${P1}/.devbot.project.jsonc"

  run python3 "${TOOL}" "${GLOBAL}"
  assert_success

  local before
  before="$(cat "${P1}/.devbot.project.jsonc")"

  run python3 "${TOOL}" "${GLOBAL}"

  assert_success
  assert_output ""
  [ "$(cat "${P1}/.devbot.project.jsonc")" = "${before}" ]
}

@test "leaves a file with both keys untouched and reports it" {
  cat > "${GLOBAL}" <<EOF
{
  "projects": ["${P1}"]
}
EOF

  printf '{ "worktrees": false, "workflow": "worktrees" }\n' > "${P1}/.devbot.project.jsonc"
  local before
  before="$(cat "${P1}/.devbot.project.jsonc")"

  run python3 "${TOOL}" "${GLOBAL}"

  assert_failure
  assert_output --partial 'both "worktrees" and "workflow" are set'
  [ "$(cat "${P1}/.devbot.project.jsonc")" = "${before}" ]
}

@test "ignores the key inside comments and strings" {
  cat > "${GLOBAL}" <<JSONC_FIXTURE
{
  "projects": ["${P1}"]
}
JSONC_FIXTURE

  cat > "${P1}/.devbot.project.jsonc" <<'JSONC_FIXTURE'
{
  // "worktrees": true
  /* "worktrees": false */
  "note": "\"worktrees\": true",
  "workflow": "trunk"
}
JSONC_FIXTURE
  local before
  before="$(cat "${P1}/.devbot.project.jsonc")"

  run python3 "${TOOL}" "${GLOBAL}"

  assert_success
  assert_output ""
  [ "$(cat "${P1}/.devbot.project.jsonc")" = "${before}" ]
}

@test "migrates a property whose value follows a comment" {
  cat > "${GLOBAL}" <<JSONC_FIXTURE
{
  "projects": ["${P1}"]
}
JSONC_FIXTURE

  cat > "${P1}/.devbot.project.jsonc" <<'JSONC_FIXTURE'
{
  "worktrees": /* the old flag */ false,
  "note": "\"worktrees\": true"
}
JSONC_FIXTURE

  run python3 "${TOOL}" "${GLOBAL}"

  assert_success
  assert_output --partial 'worktrees=false -> workflow=trunk'

  grep -qF '"workflow": /* the old flag */ "trunk"' "${P1}/.devbot.project.jsonc"
  grep -qF '"note": "\"worktrees\": true"' "${P1}/.devbot.project.jsonc"
}

@test "leaves a nested worktrees key alone" {
  cat > "${GLOBAL}" <<JSONC_FIXTURE
{
  "projects": ["${P1}"]
}
JSONC_FIXTURE

  cat > "${P1}/.devbot.project.jsonc" <<'JSONC_FIXTURE'
{
  "worktrees": false,
  "modules": { "worktrees": true }
}
JSONC_FIXTURE

  run python3 "${TOOL}" "${GLOBAL}"

  assert_success

  grep -qF '"workflow": "trunk"' "${P1}/.devbot.project.jsonc"
  grep -qF '"modules": { "worktrees": true }' "${P1}/.devbot.project.jsonc"
}

@test "preserves the original file mode" {
  cat > "${GLOBAL}" <<JSONC_FIXTURE
{
  "projects": ["${P1}"]
}
JSONC_FIXTURE

  printf '{ "worktrees": true }\n' > "${P1}/.devbot.project.jsonc"
  chmod 600 "${P1}/.devbot.project.jsonc"

  run python3 "${TOOL}" "${GLOBAL}"
  assert_success

  run python3 -c 'import os, stat, sys; print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode)))' "${P1}/.devbot.project.jsonc"
  assert_success
  assert_output "0o600"
}
