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
# The scan covers every module- and tool-owned .sh, not only init.sh. Two
# files are allowed to name a harness, and only for the reasons given: both
# inspect the runtime rather than decide what to emit.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  REPO="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"

  ALLOWED=(
    "src/agentic/autobot/install.sh"            # cron PATH: binary discovery
    "src/agentic/devbot/tools/session-usage.mcp.sh" # reports the live harness
  )
}

_is_allowed() {
  local rel="$1" entry
  for entry in "${ALLOWED[@]}"; do
    [[ "${rel}" == "${entry}" ]] && return 0
  done
  return 1
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

@test "no module or tool script names a harness" {
  local offenders="" file rel
  while IFS= read -r file; do
    rel="${file#"${REPO}/"}"
    _is_allowed "${rel}" && continue
    _reports "${file}" && offenders+="${rel}"$'\n'
  done < <(find "${REPO}/src/agentic" "${REPO}/src/tools" -name '*.sh' 2>/dev/null)

  if [[ -n "${offenders}" ]]; then
    printf 'harness-aware logic outside the documented exceptions:\n%s' "${offenders}" >&2
  fi
  assert [ -z "${offenders}" ]
}

@test "every allowed entry still exists and still reports" {
  local entry stale=""
  for entry in "${ALLOWED[@]}"; do
    [[ -f "${REPO}/${entry}" ]] || { stale+="${entry} (missing)"$'\n'; continue; }
    _reports "${REPO}/${entry}" || stale+="${entry} (clean now — remove it)"$'\n'
  done
  if [[ -n "${stale}" ]]; then
    printf 'allowlist needs updating:\n%s' "${stale}" >&2
  fi
  assert [ -z "${stale}" ]
}

@test "declarative harness manifests are allowed" {
  # The rule targets logic, not declarations.
  assert [ -f "${REPO}/src/agentic/tools-mcp/harness-assets.json" ]
  grep -q '"mcp"' "${REPO}/src/agentic/tools-mcp/harness-assets.json"
  # {harness-dir} is a token the harness resolves, not a hardcoded path.
  run grep -l '{harness-dir}' "${REPO}"/src/agentic/*/mcp.json
  assert_success
}
