#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/migrations_tests.bats
# Versioned config migrations: discovery, up/down parity, range selection,
# ordering, and failure propagation.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  MODULE_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  MIGRATIONS="${MODULE_DIR}/migrations.sh"
  SANDBOX="$(mktemp -d)"
  CONFIG="${SANDBOX}/.devbot.global.jsonc"
  printf '{}\n' > "${CONFIG}"

  export DEV_BOT_ROOT="${SANDBOX}"
  # shellcheck source=/dev/null
  source "${MIGRATIONS}"
}

teardown() {
  rm -rf "${SANDBOX}"
}

# Throwaway 2.x migrations: each records its name so a test can assert the
# exact set and order that ran. Versions sit above the shipped 1.x pairs so a
# range test never executes the real migrations.
_fakes() {
  MARKER="${SANDBOX}/ran"
  export MARKER
  # shellcheck disable=SC2317  # called by migrate through dynamic dispatch
  function migration_up-2.0.0 { echo "up-2.0.0" >> "${MARKER}"; }
  # shellcheck disable=SC2317
  function migration_down-2.0.0 { echo "down-2.0.0" >> "${MARKER}"; }
  # shellcheck disable=SC2317
  function migration_up-2.1.0 { echo "up-2.1.0" >> "${MARKER}"; }
  # shellcheck disable=SC2317
  function migration_down-2.1.0 { echo "down-2.1.0" >> "${MARKER}"; }
}

@test "discovery finds the shipped up and down versions" {
  run _migration_versions up
  assert_success
  assert_output --partial "1.9.0"
  assert_output --partial "1.15.0"

  run _migration_versions down
  assert_success
  assert_output --partial "1.9.0"
  assert_output --partial "1.15.0"
}

@test "every up migration has a down migration and vice versa" {
  run _migration_parity
  assert_success
  assert_output ""
}

@test "an up without a down fails parity and names the missing function" {
  # shellcheck disable=SC2317
  function migration_up-9.9.9 { :; }

  run _migration_parity
  assert_failure
  assert_output --partial "migration_down-9.9.9"
}

@test "a down without an up fails parity and names the missing function" {
  # shellcheck disable=SC2317
  function migration_down-9.9.8 { :; }

  run _migration_parity
  assert_failure
  assert_output --partial "migration_up-9.9.8"
}

@test "migrate excludes the from version and the range above the target" {
  _fakes

  run migrate 2.0.0 2.1.0 "${CONFIG}"
  assert_success
  run cat "${MARKER}"
  assert_output "up-2.1.0"
}

@test "migrate runs every crossed version in ascending order" {
  _fakes

  run migrate 1.99.0 2.1.0 "${CONFIG}"
  assert_success
  run cat "${MARKER}"
  assert_output "up-2.0.0
up-2.1.0"
}

@test "migrate runs nothing when the version is unchanged" {
  _fakes

  run migrate 2.1.0 2.1.0 "${CONFIG}"
  assert_success
  [[ ! -e "${MARKER}" ]]
}

@test "a downgrade runs the down migrations in descending order" {
  _fakes

  run migrate 2.1.0 1.99.0 "${CONFIG}"
  assert_success
  run cat "${MARKER}"
  assert_output "down-2.1.0
down-2.0.0"
}

@test "migrate_down is the explicit reverse entry point" {
  _fakes

  run migrate_down 2.1.0 2.0.0 "${CONFIG}"
  assert_success
  run cat "${MARKER}"
  assert_output "down-2.1.0"
}

@test "a failed migration makes the run non-zero" {
  # shellcheck disable=SC2317
  function migration_up-3.0.0 { return 1; }
  # shellcheck disable=SC2317
  function migration_down-3.0.0 { :; }

  run migrate 2.9.0 3.0.0 "${CONFIG}"
  assert_failure
}

@test "version comparison orders 1.9.0 before 1.10.0" {
  run _migration_version_lt 1.9.0 1.10.0
  assert_success
  run _migration_version_lt 1.10.0 1.9.0
  assert_failure
}

@test "version comparison handles a four-part zero-major version" {
  run _migration_version_lt 0.1.2.3 0.1.2.4
  assert_success
  run _migration_version_lt 0.1.10 0.1.9
  assert_failure
}

@test "version checks accept a v-prefixed release tag" {
  run _migration_version_lt v1.9.0 1.10.0
  assert_success
  run _migration_version_lt vnot-a-version 1.10.0
  assert_failure
  run _migration_valid_version v1.14.0
  assert_success
  run _migration_valid_version vnot-a-version
  assert_failure
}

@test "a non-numeric version range is rejected instead of compared" {
  run migrate 1.9.0 not-a-version "${CONFIG}"
  assert_failure
  assert_output --partial "non-numeric"
}

@test "a failed migration stops the rest of the range" {
  MARKER="${SANDBOX}/ran"
  export MARKER
  # shellcheck disable=SC2317
  function migration_up-2.0.0 { return 1; }
  # shellcheck disable=SC2317
  function migration_down-2.0.0 { :; }
  # shellcheck disable=SC2317
  function migration_up-2.1.0 { echo "up-2.1.0" >> "${MARKER}"; }
  # shellcheck disable=SC2317
  function migration_down-2.1.0 { :; }

  run migrate 1.99.0 2.1.0 "${CONFIG}"
  assert_failure
  [[ ! -e "${MARKER}" ]]
}

@test "the 1.9.0 up migration skips a missing global config" {
  run migration_up-1.9.0 "${SANDBOX}/missing.jsonc"
  assert_success
}

@test "the run phase loads the migration set from the given source file" {
  local source="${SANDBOX}/migrations.sh"
  export MARKER="${SANDBOX}/phase-ran"
  cat > "${source}" <<EOF
source "${MIGRATIONS}"
function migration_up-3.0.0 { printf 'ran-3.0.0\n' > "\${MARKER}"; }
function migration_down-3.0.0 { :; }
EOF

  run _migration_run_phase 2.9.0 3.0.0 "${CONFIG}" "${source}"
  assert_success
  run cat "${MARKER}"
  assert_output "ran-3.0.0"
}
