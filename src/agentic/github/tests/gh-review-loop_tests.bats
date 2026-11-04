#!/usr/bin/env bats
# =============================================================================
# src/agentic/github/tests/gh-review-loop_tests.bats
# Guards the Copilot review loop's contract, now owned by the
# `devbot:gh-review-loop` skill (it used to live in the auto-dev command):
# request after creation, verify from the timeline with an event-id cursor,
# fall back to the GraphQL mutation, poll on the documented cadence, reply in
# the fixed format, and finish by squashing and handing over the force-push.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "${TEST_DIR}/.." && pwd)"
  SKILL="${MODULE_DIR}/skills/gh-review-loop/SKILL.md"
  COMMAND="${MODULE_DIR}/commands/gh-review-loop.md"

  # Prose wraps: grep each assertion against one flattened line.
  SKILL_FLAT="${BATS_TEST_TMPDIR}/skill-flat.md"
  tr '\n' ' ' < "${SKILL}" | tr -s ' ' > "${SKILL_FLAT}"
}

@test "skill frontmatter names devbot:gh-review-loop" {
  [ -f "${SKILL}" ]
  grep -q '^name: devbot:gh-review-loop' "${SKILL}"
}

@test "command frontmatter names devbot:gh-review-loop" {
  [ -f "${COMMAND}" ]
  grep -q '^name: devbot:gh-review-loop' "${COMMAND}"
}

@test "command points at the skill instead of carrying the mechanics" {
  grep -q 'devbot:gh-review-loop` skill' "${COMMAND}"
  ! grep -q 'requestReviews' "${COMMAND}"
  ! grep -q 'pull_request_review_id' "${COMMAND}"
}

@test "skill carries the review loop mechanics" {
  grep -q '@copilot' "${SKILL}"
  grep -q 'requestReviews' "${SKILL}"
  grep -q 'pull_request_review_id' "${SKILL}"
  grep -q '\*\*Review effort:\*\*' "${SKILL}"
}

@test "skill never requests the reviewer on PR creation" {
  grep -qi 'must never go on' "${SKILL_FLAT}"
  ! grep -q 'gh pr create --reviewer' "${SKILL}"
}

@test "review loop verifies a request registered by reading the timeline" {
  # Stable signals only: event names, the scoped login and the baseline timestamp.
  grep -q 'review_requested' "${SKILL}"
  grep -q 'copilot_work_started' "${SKILL}"
  # Scoped to the bot, so a human reviewer's request cannot pass for Copilot's.
  grep -q 'requested_reviewer.login == "Copilot"' "${SKILL}"
  # And the selected event must be newer than the cursor captured before the
  # request — an older round's event cannot satisfy the check.
  grep -q -- '-gt "${since:-0}"' "${SKILL}"
  grep -q 'issues/<pr>/timeline' "${SKILL}"
  # An event-id cursor, captured before the request: same-second timestamps
  # cannot reject a real request, and an older round's event cannot pass for it.
  grep -q 'since=' "${SKILL}"
  # --paginate runs --jq per page, so the per-page maxima are reduced here.
  grep -q -- '--paginate' "${SKILL}"
  grep -q 'sort -n' "${SKILL}"
  grep -q 'tail -1' "${SKILL}"
  cursor_line="$(grep -n 'since=' "${SKILL}" | cut -d: -f1 | head -1)"
  request_line="$(grep -n 'gh pr edit <pr> --add-reviewer' "${SKILL}" | cut -d: -f1 | head -1)"
  [ -n "${cursor_line}" ] && [ -n "${request_line}" ]
  [ "${cursor_line}" -lt "${request_line}" ]
}

@test "review loop falls back to the GraphQL request when nothing registered" {
  grep -q 'requestReviews' "${SKILL}"
  grep -q 'botIds' "${SKILL}"
  # The fallback must be executable: declared variables, bound by `gh api graphql`.
  grep -q 'gh api graphql' "${SKILL}"
  grep -q 'mutation($pr:ID!,$bot:ID!)' "${SKILL}"
  grep -q -- '-f bot=' "${SKILL}"
  # The fallback follows the timeline check, it does not replace it.
  timeline_line="$(grep -n 'issues/<pr>/timeline' "${SKILL}" | cut -d: -f1 | head -1)"
  fallback_line="$(grep -n 'requestReviews' "${SKILL}" | cut -d: -f1 | head -1)"
  [ -n "${timeline_line}" ] && [ -n "${fallback_line}" ]
  [ "${timeline_line}" -lt "${fallback_line}" ]
  # The baseline is re-captured before the mutation, so its own event still counts.
  recapture_line="$(grep -n 're-record' "${SKILL}" | cut -d: -f1 | head -1)"
  [ -n "${recapture_line}" ]
  [ "${recapture_line}" -lt "${fallback_line}" ]
}

@test "review loop replies succinctly and resolves each thread" {
  grep -q 'one to three bullet points only' "${SKILL_FLAT}"
  grep -q 'each line at most 72 characters' "${SKILL_FLAT}"
  grep -q 'no prose' "${SKILL_FLAT}"
  grep -q 'then resolve the thread' "${SKILL_FLAT}"
  grep -q 'in the same format' "${SKILL_FLAT}"
}

@test "review loop polls Copilot every minute, 60 times" {
  grep -q '1 minute after each request before the first check' "${SKILL_FLAT}"
  grep -q 'maximum of 60 checks per request' "${SKILL_FLAT}"
  # The old cadence must be gone, not merely outnumbered by the new one.
  ! grep -q 'maximum of 12 checks' "${SKILL_FLAT}"
}

@test "review loop finishes one step before the merge" {
  grep -q 'squash the fixups' "${SKILL_FLAT}"
  grep -q 'push --force-with-lease' "${SKILL_FLAT}"
  grep -q 'Never merge' "${SKILL_FLAT}"
}
