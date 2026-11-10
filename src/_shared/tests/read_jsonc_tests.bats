#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/read_jsonc_tests.bats
# read_jsonc.py is the config reader every module shares. It strips `//` and
# `/* */` comments *and* JSONC's trailing commas, without touching a comma that
# lives inside a string.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  READER="${PROJECT_ROOT}/src/_shared/read_jsonc.py"
  SANDBOX="$(mktemp -d)"
  CONF="${SANDBOX}/config.jsonc"

  command -v python3 &>/dev/null || skip "python3 not installed"
}

teardown() {
  rm -r "${SANDBOX}" 2>/dev/null || true
}

@test "a trailing comma before a closing brace is accepted" {
  printf '{\n  "a": 1,\n}\n' > "${CONF}"

  run python3 "${READER}" "${CONF}" a
  assert_success
  assert_output "1"
}

@test "a trailing comma before a closing bracket is accepted" {
  printf '{\n  "a": [1, 2,],\n}\n' > "${CONF}"

  run python3 "${READER}" "${CONF}" a
  assert_success
  assert_output "[1, 2]"
}

@test "comments and trailing commas together are accepted" {
  cat > "${CONF}" <<'JSONC'
{
  // the port to bind
  "port": 8080,
  "hosts": ["a", "b",], /* both */
}
JSONC

  run python3 "${READER}" "${CONF}" port
  assert_success
  assert_output "8080"
  run python3 "${READER}" "${CONF}" hosts
  assert_success
  assert_output '["a", "b"]'
}

@test "a comma inside a string is left alone" {
  printf '{\n  "note": "x,]y",\n}\n' > "${CONF}"

  run python3 "${READER}" "${CONF}" note
  assert_success
  assert_output "x,]y"
}

@test "comment markers inside a string are left alone" {
  cat > "${CONF}" <<'JSONC'
{
  "url": "https://example.test/a//b",
  "boast": "/* not a comment */",
}
JSONC

  run python3 "${READER}" "${CONF}" url
  assert_success
  assert_output "https://example.test/a//b"
  run python3 "${READER}" "${CONF}" boast
  assert_success
  assert_output "/* not a comment */"
}

@test "a nested value is addressed by section then key" {
  printf '{\n  "workspace": {\n    "workflow": "trunk",\n  },\n}\n' > "${CONF}"

  run python3 "${READER}" "${CONF}" workspace workflow
  assert_success
  assert_output "trunk"
}

@test "genuinely invalid JSON still fails" {
  printf '{\n  "a": ,\n}\n' > "${CONF}"

  run python3 "${READER}" "${CONF}" a
  assert_failure
}

@test "a comma with no member before it is still invalid" {
  printf '{ "a": [ , ] }\n' > "${CONF}"

  run python3 "${READER}" "${CONF}" a
  assert_failure

  printf '{ , }\n' > "${CONF}"
  run python3 "${READER}" "${CONF}"
  assert_failure

  printf '{ "a": [1, ,] }\n' > "${CONF}"
  run python3 "${READER}" "${CONF}" a
  assert_failure
}
