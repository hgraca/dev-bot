#!/usr/bin/env bats
# =============================================================================
# src/tools/devbot-cli/tests/init_config_tests.bats
# Regression (audit-32/33 FAIL): search-memories' default collection name must
# agree with qmd/init.sh. Fix (b): devbot-cli/init.sh must inject a missing
# project_name into an EXISTING .devbot.project.jsonc (harness fixtures write
# one with only harness/modules), defaulting to the project dir basename —
# otherwise search-memories resolves a collection that qmd never registered.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../../.." && pwd)"
  INIT_SH="${PROJECT_ROOT}/src/tools/devbot-cli/init.sh"
  SANDBOX="$(mktemp -d)"
}

teardown() {
  rm -rf "${SANDBOX}" 2>/dev/null || true
}

@test "init.sh: injects project_name = dir basename into existing config lacking it" {
  local project="${SANDBOX}/app"
  mkdir -p "${project}"
  # Fixture shape (harness set_harness writes harness + modules only).
  cat > "${project}/.devbot.project.jsonc" <<'JSON'
{"harness": "opencode", "modules": {"claudecode": false}}
JSON

  run bash "${INIT_SH}" "${project}"
  assert_success

  local name
  name="$(python3 "${PROJECT_ROOT}/src/_shared/read_jsonc.py" "${project}/.devbot.project.jsonc" project_name)"
  assert_equal "${name}" "app"
  # Existing keys preserved.
  run python3 "${PROJECT_ROOT}/src/_shared/read_jsonc.py" "${project}/.devbot.project.jsonc" harness
  assert_output "opencode"
}

@test "init.sh: leaves existing project_name untouched" {
  local project="${SANDBOX}/named"
  mkdir -p "${project}"
  cat > "${project}/.devbot.project.jsonc" <<'JSON'
{
  // comment preserved
  "project_name": "my-cool-project",
  "harness": "opencode"
}
JSON

  run bash "${INIT_SH}" "${project}"
  assert_success

  local name
  name="$(python3 "${PROJECT_ROOT}/src/_shared/read_jsonc.py" "${project}/.devbot.project.jsonc" project_name)"
  assert_equal "${name}" "my-cool-project"
  grep -q "// comment preserved" "${project}/.devbot.project.jsonc"
}

@test "init.sh: second run is idempotent (no duplicate project_name)" {
  local project="${SANDBOX}/app"
  mkdir -p "${project}"
  cat > "${project}/.devbot.project.jsonc" <<'JSON'
{"harness": "opencode"}
JSON

  run bash "${INIT_SH}" "${project}"
  assert_success
  run bash "${INIT_SH}" "${project}"
  assert_success

  # project_name appears exactly once.
  local count
  count="$(grep -c '"project_name"' "${project}/.devbot.project.jsonc" || true)"
  assert_equal "${count}" "1"
}
