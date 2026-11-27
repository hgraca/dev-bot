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

@test "the 1.17.0 up migration seeds project configs only" {
  export DEV_BOT_ROOT="$(cd "${MODULE_DIR}/../.." && pwd)"

  mkdir -p "${SANDBOX}/core" "${SANDBOX}/portal"
  printf '{\n  "harness": "opencode"\n}\n' > "${SANDBOX}/core/.devbot.project.jsonc"
  printf '{\n  "autobot": {"poll_jira": true}\n}\n' > "${SANDBOX}/portal/.devbot.project.jsonc"
  printf '{"projects": ["core", "portal"]}\n' > "${CONFIG}"

  run migration_up-1.17.0 "${CONFIG}"
  assert_success

  run python3 "${DEV_BOT_ROOT}/src/_shared/read_jsonc.py" "${SANDBOX}/core/.devbot.project.jsonc" autobot
  assert_success
  assert_output --partial '"poll_jira": false'

  run python3 "${DEV_BOT_ROOT}/src/_shared/read_jsonc.py" "${SANDBOX}/portal/.devbot.project.jsonc" autobot
  assert_success
  assert_output --partial '"poll_jira": true'

  # The global config is not a project config; `autobot` must not land in it.
  refute grep -q autobot "${CONFIG}"

  # The down half is deliberately inert, so the seeded block survives it.
  run migration_down-1.17.0 "${CONFIG}"
  assert_success
  run python3 "${DEV_BOT_ROOT}/src/_shared/read_jsonc.py" "${SANDBOX}/core/.devbot.project.jsonc" autobot
  assert_success
}

@test "the 1.18.0 up migration adds the slack keys to seeded blocks only" {
  export DEV_BOT_ROOT="$(cd "${MODULE_DIR}/../.." && pwd)"

  mkdir -p "${SANDBOX}/core" "${SANDBOX}/portal" "${SANDBOX}/profiled" "${SANDBOX}/arrayed"
  # A project that never got the block: the whole thing is seeded.
  printf '{\n  "harness": "opencode"\n}\n' > "${SANDBOX}/core/.devbot.project.jsonc"
  # A project seeded by 1.17.0, before the slack keys existed.
  printf '{\n  "autobot": {"poll_jira": true}\n}\n' > "${SANDBOX}/portal/.devbot.project.jsonc"
  # A project whose values spell the key names: still nothing is mentioned.
  printf '{\n  "autobot": {"jira_assignees": ["poll_slack", "slack_user_email"]}\n}\n' \
    > "${SANDBOX}/arrayed/.devbot.project.jsonc"
  # A project on a global profile: its keys belong in the profile, not here.
  printf '{\n  "autobot": "gete-jira"\n}\n' > "${SANDBOX}/profiled/.devbot.project.jsonc"
  printf '{"projects": ["core", "portal", "profiled", "arrayed"]}\n' > "${CONFIG}"

  run migration_up-1.18.0 "${CONFIG}"
  assert_success
  assert_output --partial "slack keys added to 3 project config(s), 1 already had them"

  run grep -F '"poll_slack": false' "${SANDBOX}/core/.devbot.project.jsonc"
  assert_success
  run grep -F '"slack_bot_token": "${SLACK_BOT_TOKEN}"' "${SANDBOX}/core/.devbot.project.jsonc"
  assert_success

  # The seeded block keeps its value and gains the commented keys beside it.
  run python3 "${DEV_BOT_ROOT}/src/_shared/read_jsonc.py" "${SANDBOX}/portal/.devbot.project.jsonc" autobot
  assert_success
  assert_output --partial '"poll_jira": true'
  refute_output --partial '"poll_slack"' # commented out, so not part of the parsed object
  run grep -F '"slack_user_email": "you@example.com"' "${SANDBOX}/portal/.devbot.project.jsonc"
  assert_success

  # A value that spells a key name does not suppress its discoverability line.
  run grep -F '"poll_slack": false' "${SANDBOX}/arrayed/.devbot.project.jsonc"
  assert_success

  # A profile reference is left exactly as it was.
  run cat "${SANDBOX}/profiled/.devbot.project.jsonc"
  assert_output '{
  "autobot": "gete-jira"
}'

  # The global config is not a project config.
  refute grep -q autobot "${CONFIG}"

  # Idempotent: a second run changes nothing.
  local once
  once="$(cat "${SANDBOX}/portal/.devbot.project.jsonc")"
  run migration_up-1.18.0 "${CONFIG}"
  assert_success
  assert_output --partial "slack keys added to 0 project config(s), 4 already had them"
  [ "$(cat "${SANDBOX}/portal/.devbot.project.jsonc")" = "${once}" ]

  # The down half is deliberately inert, so the keys survive it.
  run migration_down-1.18.0 "${CONFIG}"
  assert_success
  run grep -F '"poll_slack": false' "${SANDBOX}/portal/.devbot.project.jsonc"
  assert_success
}

@test "the 1.18.0 up migration fails on a read-only project config" {
  export DEV_BOT_ROOT="$(cd "${MODULE_DIR}/../.." && pwd)"

  mkdir -p "${SANDBOX}/locked"
  printf '{\n  "autobot": {"poll_jira": true}\n}\n' > "${SANDBOX}/locked/.devbot.project.jsonc"
  chmod 444 "${SANDBOX}/locked/.devbot.project.jsonc"
  printf '{"projects": ["locked"]}\n' > "${CONFIG}"

  run migration_up-1.18.0 "${CONFIG}"
  assert_failure
  assert_output --partial "could not add the slack keys"

  # The read-only config is left exactly as it was.
  refute grep -q 'poll_slack' "${SANDBOX}/locked/.devbot.project.jsonc"
  chmod 644 "${SANDBOX}/locked/.devbot.project.jsonc"
}

@test "the 1.20.0 up migration keys the kubectl catalogue by cluster name" {
  export DEV_BOT_ROOT="$(cd "${MODULE_DIR}/../.." && pwd)"

  cat > "${CONFIG}" <<'JSONC'
{
  // machine-wide catalogue
  "harness": "opencode-v2",
  "kubectl": {
    "profile": "devbot-agent",
    "clusters": [
      { "name": "gete", "context": "gete-prod-ro", "region": "eu-central-1" },
      { "name": "gete-dev", "context": "gete-staging-rw", "region": "eu-central-1" }
    ]
  }
}
JSONC

  run migration_up-1.20.0 "${CONFIG}"
  assert_success

  run python3 "${DEV_BOT_ROOT}/src/_shared/read_jsonc.py" "${CONFIG}" kubectl clusters
  assert_success
  assert_output --partial '"gete":'
  assert_output --partial '"gete-dev":'
  # The array's one name was both identifiers, so the object keeps it as the AWS
  # cluster and uses the same string as the key.
  assert_output --partial '"name": "gete"'
  # The rewrite is textual, so the comment above the block survives.
  run grep -c '// machine-wide catalogue' "${CONFIG}"
  assert_output "1"

  # A second run has nothing to do and says so.
  run migration_up-1.20.0 "${CONFIG}"
  assert_success
  assert_output --partial "already in the target shape"

  # The down half rebuilds the array, name included.
  run migration_down-1.20.0 "${CONFIG}"
  assert_success
  run python3 "${DEV_BOT_ROOT}/src/_shared/read_jsonc.py" "${CONFIG}" kubectl clusters
  assert_output --partial '"name": "gete-dev"'
}

# ── 1.25.0: the herdr and ghostty modules ship disabled ─────────────────────
# The module scripts run before the reconciler, so a config that names neither
# module would provision both before the dist default lands. The migration writes
# the explicit `false` first — and only where the config names the module nowhere,
# so a value the machine set itself survives.

@test "the 1.25.0 up migration disables herdr and ghostty" {
  export DEV_BOT_ROOT="$(cd "${MODULE_DIR}/../.." && pwd)"

  cat > "${CONFIG}" <<'JSONC'
{
  // machine config
  "modules": {
    "atlassian": false,
    "herdr": true
  },
  "auto_update": true
}
JSONC

  run migration_up-1.25.0 "${CONFIG}"
  assert_success
  assert_output --partial "herdr and ghostty modules false"

  run python3 "${DEV_BOT_ROOT}/src/_shared/read_jsonc.py" "${CONFIG}" modules
  assert_success
  # The machine enabled herdr itself: that choice stands.
  assert_output --partial '"herdr": true'
  assert_output --partial '"ghostty": false'
  assert_output --partial '"atlassian": false'

  # Textual surgery: the comment and the untouched key survive.
  run grep -c '// machine config' "${CONFIG}"
  assert_output "1"
  run python3 "${DEV_BOT_ROOT}/src/_shared/read_jsonc.py" "${CONFIG}" auto_update
  assert_output "true"

  # Running it again is a no-op, not a second edit.
  run migration_up-1.25.0 "${CONFIG}"
  assert_success
  run grep -c '"ghostty"' "${CONFIG}"
  assert_output "1"
}

@test "the 1.25.0 down migration touches nothing" {
  # Neither module exists below 1.25.0: the keys are inert there, and undoing
  # them would have to guess which value the machine wanted.
  export DEV_BOT_ROOT="$(cd "${MODULE_DIR}/../.." && pwd)"
  printf '{\n  "modules": {\n    "herdr": false,\n    "ghostty": false\n  }\n}\n' > "${CONFIG}"
  cp "${CONFIG}" "${SANDBOX}/before"

  run migration_down-1.25.0 "${CONFIG}"

  assert_success
  assert_output --partial "nothing to undo"
  cmp -s "${SANDBOX}/before" "${CONFIG}"
}

@test "the 1.25.0 migration skips a machine with no global config" {
  export DEV_BOT_ROOT="$(cd "${MODULE_DIR}/../.." && pwd)"

  run migration_up-1.25.0 "${SANDBOX}/absent.jsonc"
  assert_success
  assert_output --partial "no global config"
}

@test "the 1.25.0 up migration fails on a config it cannot rewrite" {
  export DEV_BOT_ROOT="$(cd "${MODULE_DIR}/../.." && pwd)"
  printf '{\n  "modules": {\n' > "${CONFIG}"

  run migration_up-1.25.0 "${CONFIG}"
  assert_failure
  assert_output --partial "could not set the herdr/ghostty module defaults"

  # Left exactly as it was.
  run cat "${CONFIG}"
  assert_output "{
  \"modules\": {"
}
