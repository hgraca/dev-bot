#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/harness-agnostic-modules_tests.bats
# Modules declare; the selected harness applies.
#
# A module must never name a harness in its logic. Asking "is opencode
# selected?" is how the opencode-v2 harness lost every MCP wrapper: each module
# skipped, and the servers pointed at scripts that did not exist (exit 127).
#
# Declarations are fine and expected: plugin.opencode.json, the {harness-dir}
# and {host} tokens in mcp.json, harness-assets.json, mcp.dynamic.json.
#
# There is no allowlist: the debt that used to live here is gone, and a new
# violation fails CI.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  REPO="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
}

_reports() {
  local file="$1"
  grep -qE '_devbot_get_harness|_aws_harness_disabled|_netsuite_selected|_netsuite_disabled' "${file}" && return 0
  grep -qE 'index\("(opencode|claudecode)"\)' "${file}" && return 0
  # Any non-comment path into a harness directory is the module making a
  # harness-shaped decision, whatever it does with it.
  grep -vE '^[[:space:]]*#' "${file}" | grep -qE '\.(opencode|claude)/' && return 0
  return 1
}

@test "no module init names a harness" {
  local offenders="" file rel
  while IFS= read -r file; do
    rel="${file#"${REPO}/"}"
    _reports "${file}" && offenders+="${rel}"$'\n'
  done < <(find "${REPO}/src/agentic" "${REPO}/src/tools" -name 'init.sh' 2>/dev/null)

  if [[ -n "${offenders}" ]]; then
    printf 'harness-aware logic in module init:\n%s' "${offenders}" >&2
  fi
  assert [ -z "${offenders}" ]
}

@test "declarative harness manifests are allowed" {
  # The rule targets logic, not declarations.
  assert [ -f "${REPO}/src/agentic/tools-mcp/harness-assets.json" ]
  grep -q '"mcp"' "${REPO}/src/agentic/tools-mcp/harness-assets.json"
  # {harness-dir} is a token the harness resolves, not a hardcoded path.
  run grep -l '{harness-dir}' "${REPO}"/src/agentic/*/mcp.json
  assert_success
}
