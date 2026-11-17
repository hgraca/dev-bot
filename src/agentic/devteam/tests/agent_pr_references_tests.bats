#!/usr/bin/env bats
# =============================================================================
# src/agentic/devteam/tests/agent_pr_references_tests.bats
# Guards how the primary agents talk about pull requests: the exact markdown
# link form, and the rule that a handover lists every pull request still open.
#
# A bare `#109` or a naked URL cannot be read out of a chat UI, and a handover
# that stays silent about an open pull request loses it.
#
# Run from project root:
#   bats src/agentic/devteam/tests/agent_pr_references_tests.bats
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  ROOT="$(cd "$TEST_DIR/../../../.." && pwd)"
  DEVBOOT_AGENT="${ROOT}/src/agentic/devbot/agents/devbot.md"
  TEAMLEAD_AGENT="${ROOT}/src/agentic/devteam/agents/teamlead.md"
  # Prose wraps: grep each assertion against one flattened line per file.
  DEVBOOT_FLAT="${BATS_TEST_TMPDIR}/devbot-flat.md"
  TEAMLEAD_FLAT="${BATS_TEST_TMPDIR}/teamlead-flat.md"
  tr '\n' ' ' < "${DEVBOOT_AGENT}" | tr -s ' ' > "${DEVBOOT_FLAT}"
  tr '\n' ' ' < "${TEAMLEAD_AGENT}" | tr -s ' ' > "${TEAMLEAD_FLAT}"
}

@test "both primary agents carry a pull-request referencing rule" {
  local file
  for file in "${DEVBOOT_AGENT}" "${TEAMLEAD_AGENT}"; do
    run grep -qF '## Referencing pull requests' "${file}"
    assert_success
  done
}

@test "the rule mandates the owner/repo#number markdown link, never a bare handle" {
  local flat
  for flat in "${DEVBOOT_FLAT}" "${TEAMLEAD_FLAT}"; do
    run grep -qF '[GET-E/dev-bot#109](https://github.com/GET-E/dev-bot/pull/109)' "${flat}"
    assert_success
    run grep -qF 'never a bare number' "${flat}"
    assert_success
    run grep -qF 'or a naked URL' "${flat}"
    assert_success
  done
}

@test "a handover must list open pull requests, verified open first" {
  local flat
  for flat in "${DEVBOOT_FLAT}" "${TEAMLEAD_FLAT}"; do
    run grep -qF 'Every handover that leaves pull requests open names each of them in that form' "${flat}"
    assert_success
    run grep -qF 'Verify each one is still open before handing over' "${flat}"
    assert_success
    run grep -qF 'gh pr view <url> --json state' "${flat}"
    assert_success
  done
}
