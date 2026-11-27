#!/usr/bin/env bats
# =============================================================================
# bin/tests/update_migration_capture_tests.bats
# `devbot update` copies the migration tooling aside before a downgrade checks
# out an older release, so the down halves can run the tools the RUNNING release
# shipped. A helper a migration names but the capture does not copy makes every
# downgrade past that release fail — and the parity test cannot see it, because
# it only proves the down function exists.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
  SANDBOX="$(mktemp -d)"

  # A checkout-shaped tree: the real shared tools, and nothing else the capture
  # needs.
  mkdir -p "${SANDBOX}/src/_shared" "${SANDBOX}/storage/run"
  cp "${PROJECT_ROOT}/src/_shared/"*.py "${SANDBOX}/src/_shared/"
  cp "${PROJECT_ROOT}/src/_shared/migrations.sh" "${SANDBOX}/src/_shared/"
  export DEV_BOT_ROOT="${SANDBOX}"

  # The function under test, lifted out of bin/update.sh: sourcing the script
  # would run it.
  eval "$(sed -n '/^_capture_migration_tools() {/,/^}/p' "${PROJECT_ROOT}/bin/update.sh")"
}

teardown() {
  rm -rf "${SANDBOX}"
}

# Every python helper the shipped migrations reach for, by file name.
_helpers_named_by_migrations() {
  grep -oE '(_migration_tools_dir\)|src/_shared)/[a-z_]+\.py' \
    "${PROJECT_ROOT}/src/_shared/migrations.sh" \
    | sed 's|.*/||' | sort -u
}

@test "the capture copies every helper the shipped migrations name" {
  run _capture_migration_tools
  assert_success
  local dir="${output}"

  local helper
  local missing=0
  while IFS= read -r helper; do
    if [[ ! -f "${dir}/${helper}" ]]; then
      echo "not captured: ${helper}"
      missing=1
    fi
  done < <(_helpers_named_by_migrations)

  [ "${missing}" -eq 0 ]
}

@test "the capture list is not trivially complete (guards a stale derivation)" {
  # If the derivation broke, the loop above would pass over an empty list.
  local n
  n="$(_helpers_named_by_migrations | wc -l | tr -d ' ')"
  [ "${n}" -ge 4 ]
}

@test "the 1.25.0 migration runs from a captured tool set" {
  run _capture_migration_tools
  assert_success
  local dir="${output}"

  # A downgrade points the migration at the captured copy, not the checkout.
  DEV_BOT_MIGRATION_TOOLS_DIR="${dir}" run bash -c "
    export DEV_BOT_ROOT='${PROJECT_ROOT}'
    export DEV_BOT_MIGRATION_TOOLS_DIR='${dir}'
    source '${PROJECT_ROOT}/src/_shared/migrations.sh'
    printf '{\n  \"modules\": {}\n}\n' >'${SANDBOX}/global.jsonc'
    migration_up-1.25.0 '${SANDBOX}/global.jsonc'
    python3 '${dir}/read_jsonc.py' '${SANDBOX}/global.jsonc' modules
  "

  assert_success
  assert_output --partial '"herdr": false'
  assert_output --partial '"ghostty": false'
}
