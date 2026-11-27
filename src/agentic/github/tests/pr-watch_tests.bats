#!/usr/bin/env bats
# =============================================================================
# src/agentic/github/tests/pr-watch_tests.bats
# Guards pr-watch's contract: the metadata block the MCP farm reads, the exit
# codes that carry the outcome, and the digest lines a caller relies on. gh is
# stubbed, so no network and no authentication are needed.
# =============================================================================

setup() {
    bats_load_library bats-support
    bats_load_library bats-assert

    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
    TOOL="$MODULE_DIR/tools/pr-watch.mcp.sh"

    STUBS="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$STUBS"
    cat >"$STUBS/gh" <<'STUB'
#!/usr/bin/env bash
# Scenario is chosen by PR_WATCH_SCENARIO: review | fail | none
scenario="${PR_WATCH_SCENARIO:-none}"
case "$*" in
  "repo view"*"--json defaultBranchRef"*) echo "GET-E/dev-bot $*" >> "@REPOARG@"; echo "main" ;;
  "repo view"*) echo "GET-E/dev-bot" ;;
  "api users/"*)
      if [ -n "${PR_WATCH_BOT_BROKEN:-}" ]; then echo "boom" >&2; exit 1; fi
      echo "BOT_NODE_ID" ;;
  "api --paginate"*"timeline"*)
      [ -f "@MARKER@" ] && echo "2026-01-01T00:00:00Z" ;;

  "pr view"*"--json commits"*) echo "2025-12-31T00:00:00Z" ;;
  "pr view"*"--json isDraft,mergeable,mergeStateStatus"*)
      printf '{"isDraft":%s,"mergeable":"%s","mergeStateStatus":"%s"}\n' \
          "${PR_IS_DRAFT:-false}" "${PR_MERGEABLE:-MERGEABLE}" "${PR_MERGE_STATE-CLEAN}"
      ;;
  "pr view"*)
      printf '{"number":172,"state":"OPEN","isDraft":false,"reviewDecision":"%s","headRefName":"feat/x","baseRefName":"main","title":"test pr","url":"https://example/pr/172"}\n' "${PR_REVIEW_DECISION:-}"
      ;;
  "api graphql"*)
      touch "@MARKER@"
      echo '{"data":{"requestReviews":{"clientMutationId":null}}}'
      ;;
  "api "*"/pulls/"*"/comments"*)
      if [ "$scenario" = comments ] || [ "$scenario" = approved_comments ]; then
          echo "9001"
      elif [ "$scenario" = comments_broken ]; then
          echo "boom" >&2
          exit 1
      fi ;;
  "api "*"/reviews"*)
      if [ "$scenario" = review ]; then
          echo '{"id":77,"user":"copilot-pull-request-reviewer[bot]","state":"COMMENTED","submitted_at":"2026-01-01T00:00:00Z","body":"Found a null deref in the retry loop."}'
      elif [ "$scenario" = comments ]; then
          echo '{"id":78,"user":"copilot-pull-request-reviewer[bot]","state":"COMMENTED","submitted_at":"2026-01-01T00:00:00Z","body":""}'
      elif [ "$scenario" = approved ]; then
          echo '{"id":79,"user":"copilot-pull-request-reviewer[bot]","state":"APPROVED","submitted_at":"2026-01-01T00:00:00Z","body":"### Approved\n\n**No open issues** found in this pull request."}'
      elif [ "$scenario" = clean_comment ]; then
          echo '{"id":80,"user":"copilot-pull-request-reviewer[bot]","state":"COMMENTED","submitted_at":"2026-01-01T00:00:00Z","body":"**No open issues** — this reads correctly."}'
      elif [ "$scenario" = body_only ]; then
          echo '{"id":81,"user":"copilot-pull-request-reviewer[bot]","state":"COMMENTED","submitted_at":"2026-01-01T00:00:00Z","body":"### 3 previously missed issues\n\n1. the retry loop drops the cursor"}'
      elif [ "$scenario" = changes ]; then
          echo '{"id":82,"user":"copilot-pull-request-reviewer[bot]","state":"CHANGES_REQUESTED","submitted_at":"2026-01-01T00:00:00Z","body":"Please fix the null deref before merging."}'
      elif [ "$scenario" = ack ]; then
          echo '{"id":83,"user":"copilot-pull-request-reviewer[bot]","state":"COMMENTED","submitted_at":"2026-01-01T00:00:00Z","body":""}'
      elif [ "$scenario" = approved_comments ]; then
          echo '{"id":84,"user":"copilot-pull-request-reviewer[bot]","state":"APPROVED","submitted_at":"2026-01-01T00:00:00Z","body":"**No open issues** found in this pull request."}'
      elif [ "$scenario" = comments_broken ]; then
          echo '{"id":85,"user":"copilot-pull-request-reviewer[bot]","state":"COMMENTED","submitted_at":"2026-01-01T00:00:00Z","body":""}'
      elif [ "$scenario" = approved_single ]; then
          echo '{"id":89,"user":"copilot-pull-request-reviewer[bot]","state":"APPROVED","submitted_at":"2026-01-01T00:00:00Z","body":"### Approved\n\n1 open issue in the retry loop."}'
      elif [ "$scenario" = approved_issues ]; then
          echo '{"id":88,"user":"copilot-pull-request-reviewer[bot]","state":"APPROVED","submitted_at":"2026-01-01T00:00:00Z","body":"### Approved\n\n2 previously missed issues in the retry loop."}'
      elif [ "$scenario" = dismissed ]; then
          echo '{"id":87,"user":"copilot-pull-request-reviewer[bot]","state":"DISMISSED","submitted_at":"2026-01-01T00:00:00Z","body":"**No open issues** found in this pull request."}'
      elif [ "$scenario" = ten_issues ]; then
          echo '{"id":86,"user":"copilot-pull-request-reviewer[bot]","state":"COMMENTED","submitted_at":"2026-01-01T00:00:00Z","body":"### 10 open issues\n\n1. the cursor is dropped"}'
      fi
      ;;
  "pr checks"*"--required"*)
      case "${PR_WATCH_REQUIRED:-$scenario}" in
        fail) echo '[{"name":"build","state":"FAILURE","bucket":"fail"}]' ;;
        fixup) echo '[{"name":"no-fixup","state":"FAILURE","bucket":"fail"}]' ;;
        fixup_ok) echo '[{"name":"no-fixup","state":"SUCCESS","bucket":"pass"}]' ;;
        fixup2) echo '[{"name":"No fixup! commits","state":"FAILURE","bucket":"fail"}]' ;;
        other) echo '[{"name":"deploy-check","state":"FAILURE","bucket":"fail"}]' ;;
        pending) echo '[{"name":"build","state":"PENDING","bucket":"pending"}]' ;;
        skipping) echo '[{"name":"lint","state":"SKIPPED","bucket":"skipping"}]' ;;
        lint_only) echo '[{"name":"lint","state":"SUCCESS","bucket":"pass"}]' ;;
        lint_test) echo '[{"name":"lint","state":"SUCCESS","bucket":"pass"},{"name":"test","state":"SUCCESS","bucket":"pass"}]' ;;
        lint_fail) echo '[{"name":"lint","state":"FAILURE","bucket":"fail"}]' ;;
        unconfigured) echo "no required checks reported on the 'feat/x' branch" >&2; exit 1 ;;
        nochecks) echo "no checks reported on the 'feat/x' branch" >&2; exit 1 ;;
        broken_query) echo "boom" >&2; exit 1 ;;
        garbage) echo "not json" ;;
        silent) exit 0 ;;
        empty) echo '[]' ;;

        *)    echo '[{"name":"build","state":"SUCCESS","bucket":"pass"}]' ;;
      esac
      ;;
  "pr checks"*)
      if [ "$scenario" = broken ]; then exit 5; fi
      if [ "$scenario" = guard_overall ]; then
          echo '[{"name":"no-fixup","state":"FAILURE","bucket":"fail"}]'
          exit 0
      fi
      if [ "$scenario" = nochecks ]; then
          echo "no checks reported on the 'feat/x' branch" >&2
          exit 1
      fi
      if [ "$scenario" = fail ] || [ "$scenario" = unconfigured ]; then
          echo '[{"name":"build","state":"FAILURE","bucket":"fail"}]'
      elif [ "$scenario" = skipping ]; then
          echo '[{"name":"lint","state":"SKIPPED","bucket":"skipping"}]'
      elif [ "$scenario" = pending ]; then
          echo '[{"name":"build","state":"PENDING","bucket":"pending"}]'
      elif [ "$scenario" = lint_only ]; then
          echo '[{"name":"lint","state":"SUCCESS","bucket":"pass"}]'
      elif [ "$scenario" = lint_test ]; then
          echo '[{"name":"lint","state":"SUCCESS","bucket":"pass"},{"name":"test","state":"SUCCESS","bucket":"pass"}]'
      elif [ "$scenario" = lint_fail ]; then
          echo '[{"name":"lint","state":"FAILURE","bucket":"fail"}]'
      elif [ "$scenario" = optional_fail ]; then
          echo '[{"name":"build","state":"SUCCESS","bucket":"pass"},{"name":"deploy-check","state":"FAILURE","bucket":"fail"}]'
      else
          echo '[{"name":"build","state":"SUCCESS","bucket":"pass"}]'
      fi
      ;;
  "api repos/"*"/branches/"*"/protection/required_status_checks"*)
      if [ -n "${PR_PROTECTION:-}" ]; then
          body=""
          for name in ${PR_PROTECTION}; do body="${body:+$body,}\"${name}\""; done
          printf '{"contexts":[%s],"checks":[]}\n' "$body"
      else
          echo "Branch not protected" >&2
          exit 1
      fi
      ;;
  "api --paginate repos/"*"/rulesets"*)
      if [ "${PR_RULESET_FAIL:-}" = 1 ]; then echo "rate limited" >&2; exit 1; fi
      for spec in ${PR_RULESETS:-}; do
          printf '{"id":%s,"target":"branch","enforcement":"active","conditions":{"ref_name":{"include":["%s"],"exclude":[]}}}\n' \
              "${spec%%=*}" "${PR_RULESET_REF:-refs/heads/main}"
      done
      ;;
  "api repos/"*"/rulesets/"*)
      id="${*##*/}"
      for spec in ${PR_RULESETS:-}; do
          if [ "${spec%%=*}" = "$id" ]; then
              printf '{"rules":[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"%s"}]}}]}\n' "${spec#*=}"
          fi
      done
      ;;
  *) echo "unexpected gh call: $*" >&2; exit 1 ;;
esac
STUB
    chmod +x "$STUBS/gh"
    sed -i "s|@MARKER@|$BATS_TEST_TMPDIR/requested|g" "$STUBS/gh"
    sed -i "s|@REPOARG@|$BATS_TEST_TMPDIR/repoarg|g" "$STUBS/gh"
    export PATH="$STUBS:$PATH"
}

@test "mcp-meta describes the tool" {
    run bash "$TOOL" mcp-meta
    assert_success
    assert_output --partial '"name":"pr-watch"'
    assert_output --partial "Exit codes"
    # The two new terminal states are advertised where the agent reads them.
    assert_output --partial "5 a review arrived with findings"
    assert_output --partial "6 all green"
    assert_output --partial "--until review|green"
}

@test "a review with findings exits 5 so the caller never reads the digest" {
    export PR_WATCH_SCENARIO=review
    run bash "$TOOL" 172 --no-request --timeout 5 --interval 1
    assert_equal "$status" 5
    assert_output --partial "PR #172"
    assert_output --partial "Latest review"
    assert_output --partial "null deref"
    assert_output --partial "outcome: review-failed"
}

@test "failing checks exit 3 and name the check" {
    export PR_WATCH_SCENARIO=fail
    run bash "$TOOL" 172 --no-request --timeout 5 --interval 1
    assert_equal "$status" 3
    assert_output --partial "Failing checks"
    assert_output --partial "build"
}

@test "no review before the timeout exits 4" {
    export PR_WATCH_SCENARIO=none
    run bash "$TOOL" 172 --no-request --timeout 1 --interval 1
    assert_equal "$status" 4
}

@test "an argument that is not a pull request is a usage error" {
    run bash "$TOOL" not-a-number
    assert_equal "$status" 2
    assert_output --partial "is not a pull request"
}

@test "json output carries the outcome" {
    export PR_WATCH_SCENARIO=review
    run bash "$TOOL" 172 --no-request --timeout 5 --interval 1 --json
    assert_equal "$status" 5
    assert_output --partial '"state": "review-failed"'
    assert_output --partial '"repository": "GET-E/dev-bot"'
}

@test "a gh failure exits 1 instead of polling to the timeout" {
    export PR_WATCH_SCENARIO=broken
    run bash "$TOOL" 172 --no-request --timeout 5 --interval 1
    assert_equal "$status" 1
    assert_output --partial "ERROR:"
}

@test "check runs not registered yet poll instead of failing" {
    # A push is followed by a window where gh answers "no checks reported" —
    # pending, not an outage: the loop must keep polling, not exit 1.
    export PR_WATCH_SCENARIO=nochecks
    run bash "$TOOL" 172 --no-request --timeout 1 --interval 1
    assert_equal "$status" 4
    refute_output --partial "ERROR:"
}

@test "a decision left over from an earlier round does not end the wait" {
    # reviewDecision carries no timestamp, so an approval from before this round
    # cannot prove the new head was reviewed.
    export PR_WATCH_SCENARIO=none
    export PR_REVIEW_DECISION=APPROVED
    run bash "$TOOL" 172 --no-request --timeout 2 --interval 1
    assert_equal "$status" 4
}

@test "a request that fails is a runtime error, not a poll to the timeout" {
    export PR_WATCH_SCENARIO=review
    export PR_WATCH_BOT_BROKEN=1
    run bash "$TOOL" 172 --timeout 5 --interval 1
    assert_equal "$status" 1
    assert_output --partial "request failed"
}

@test "a PR URL, a #number and an owner/repo#number are all accepted" {
    export PR_WATCH_SCENARIO=review
    run bash "$TOOL" "https://github.com/GET-E/dev-bot/pull/172" --no-request --timeout 5 --interval 1
    assert_equal "$status" 5
    assert_output --partial "PR #172"

    run bash "$TOOL" "#172" --no-request --timeout 5 --interval 1
    assert_equal "$status" 5

    run bash "$TOOL" "GET-E/dev-bot#172" --no-request --timeout 5 --interval 1
    assert_equal "$status" 5
}

@test "a review whose findings are only line comments exits 5" {
    export PR_WATCH_SCENARIO=comments
    run bash "$TOOL" 172 --no-request --timeout 30 --interval 1
    assert_equal "$status" 5
    assert_output --partial "Latest review"
}

@test "an optional check failure does not exit 3 when the required set passes" {
    export PR_WATCH_SCENARIO=fail
    export PR_WATCH_REQUIRED=pass
    run bash "$TOOL" 172 --no-request --timeout 2 --interval 1
    assert_equal "$status" 4
}

@test "a required check failure exits 3 even when every other check passes" {
    export PR_WATCH_SCENARIO=none
    export PR_WATCH_REQUIRED=fail
    run bash "$TOOL" 172 --no-request --timeout 5 --interval 1
    assert_equal "$status" 3
}

@test "mcp-meta outlives the MCP server's 120s default bound" {
    run bash "$TOOL" mcp-meta
    assert_success
    assert_output --partial '"timeoutMs":3600000'

    # The bound must stay ahead of the tool's own default, or the server kills
    # a normal call before the tool can report its own timeout. The default is
    # read from the source so a change that skips the help text is still seen.
    source_default="$(sed -n 's/.*"--timeout"[^)]*default=\([0-9]*\).*/\1/p' "$MODULE_DIR/tools/pr-watch.py")"
    documented="$(bash "$TOOL" --help 2>&1 | sed -n 's/.*seconds to wait (default \([0-9]*\)).*/\1/p')"
    bound="$(bash "$TOOL" mcp-meta | sed -n 's/.*"timeoutMs":\([0-9]*\).*/\1/p')"
    [ -n "$source_default" ] && [ -n "$documented" ] && [ -n "$bound" ]
    [ "$source_default" = "$documented" ]
    [ "$bound" -gt $((source_default * 1000 * 2)) ]
}

@test "json names the ignored fixup guard" {
    export PR_WATCH_SCENARIO=none
    export PR_WATCH_REQUIRED=fixup
    run bash "$TOOL" 172 --no-request --timeout 1 --interval 1 --json
    assert_equal "$status" 4
    assert_output --partial '"ignored_checks"'
    assert_output --partial '"no-fixup"'
}

@test "a repo that gates on no check is not failed by an optional red" {
    export PR_WATCH_SCENARIO=guard_overall
    export PR_WATCH_REQUIRED=unconfigured
    run bash "$TOOL" 172 --no-request --timeout 1 --interval 1
    assert_equal "$status" 4
    assert_output --partial "no-fixup"
}

@test "an ignored guard is named even when the review landed first" {
    export PR_WATCH_SCENARIO=review
    export PR_WATCH_REQUIRED=fixup
    run bash "$TOOL" 172 --no-request --timeout 5 --interval 1 --json
    assert_equal "$status" 5
    assert_output --partial '"ignored_checks"'
    assert_output --partial '"no-fixup"'
}

@test "a passing ignored guard is still named" {
    export PR_WATCH_SCENARIO=none
    export PR_WATCH_REQUIRED=fixup_ok
    run bash "$TOOL" 172 --no-request --timeout 1 --interval 1
    assert_equal "$status" 4
    assert_output --partial "Ignored checks"
    assert_output --partial "no-fixup"
}

@test "a no-fixup guard that is red by design does not exit 3" {
    export PR_WATCH_SCENARIO=none
    export PR_WATCH_REQUIRED=fixup
    run bash "$TOOL" 172 --no-request --timeout 1 --interval 1
    assert_equal "$status" 4
    assert_output --partial "Ignored checks"
    assert_output --partial "no-fixup"
}

@test "a differently named fixup guard is recognised too" {
    export PR_WATCH_SCENARIO=none
    export PR_WATCH_REQUIRED=fixup2
    run bash "$TOOL" 172 --no-request --timeout 1 --interval 1
    assert_equal "$status" 4
    assert_output --partial "No fixup! commits"
}

@test "--ignore-check excludes a red-by-design check by name" {
    export PR_WATCH_SCENARIO=none
    export PR_WATCH_REQUIRED=other
    run bash "$TOOL" 172 --no-request --timeout 1 --interval 1 --ignore-check deploy-check
    assert_equal "$status" 4
    assert_output --partial "Ignored checks"
    assert_output --partial "deploy-check"
}

@test "--ignore-check does not hide a failure it was not given" {
    export PR_WATCH_SCENARIO=none
    export PR_WATCH_REQUIRED=other
    run bash "$TOOL" 172 --no-request --timeout 5 --interval 1 --ignore-check something-else
    assert_equal "$status" 3
    assert_output --partial "deploy-check"
}

@test "--ignore-check matches a name case-insensitively" {
    export PR_WATCH_SCENARIO=none
    export PR_WATCH_REQUIRED=other
    run bash "$TOOL" 172 --no-request --timeout 1 --interval 1 --ignore-check DEPLOY-CHECK
    assert_equal "$status" 4
}

# ── --until green: the merge gate, without a review in the loop ──────────────

@test "--until green returns 6 once required checks pass and the PR is mergeable" {
    export PR_PROTECTION="build"
    export PR_WATCH_SCENARIO=none
    run bash "$TOOL" 172 --until green --timeout 5 --interval 1
    assert_equal "$status" 6
    assert_output --partial "outcome: all-green"
    assert_output --partial "checks: pass"
}

@test "--until green never asks for a review" {
    export PR_PROTECTION="build"
    export PR_WATCH_SCENARIO=none
    run bash "$TOOL" 172 --until green --timeout 5 --interval 1
    assert_equal "$status" 6
    assert_output --partial "review: skipped"
    refute [ -f "$BATS_TEST_TMPDIR/requested" ]
}

@test "--until green reports a failed required check as 3 and names it" {
    export PR_WATCH_SCENARIO=none
    export PR_WATCH_REQUIRED=fail
    run bash "$TOOL" 172 --until green --timeout 5 --interval 1
    assert_equal "$status" 3
    assert_output --partial "build"
}

@test "--until green keeps waiting while the merge state is unknown" {
    export PR_WATCH_SCENARIO=none
    export PR_MERGEABLE=UNKNOWN
    run bash "$TOOL" 172 --until green --timeout 2 --interval 1
    assert_equal "$status" 4
}

@test "--until green does not call a branch behind the default green" {
    export PR_WATCH_SCENARIO=none
    export PR_MERGE_STATE=BEHIND
    run bash "$TOOL" 172 --until green --timeout 2 --interval 1
    assert_equal "$status" 4
}

@test "--until green keeps waiting while a required check is pending" {
    export PR_WATCH_SCENARIO=none
    export PR_WATCH_REQUIRED=pending
    run bash "$TOOL" 172 --until green --timeout 2 --interval 1
    assert_equal "$status" 4
}

@test "--until green is not blocked by the fixup guard" {
    export PR_PROTECTION="no-fixup"
    export PR_WATCH_SCENARIO=none
    export PR_WATCH_REQUIRED=fixup
    run bash "$TOOL" 172 --until green --timeout 5 --interval 1
    assert_equal "$status" 6
    assert_output --partial "no-fixup"
}

@test "json names all-green too" {
    export PR_PROTECTION="build"
    export PR_WATCH_SCENARIO=none
    run bash "$TOOL" 172 --until green --timeout 5 --interval 1 --json
    assert_equal "$status" 6
    assert_output --partial '"state": "all-green"'
}

# ── What a landed review says about its own findings ─────────────────────────

@test "an approving review with a body still exits 0" {
    # Copilot attaches a body to every review, an approval included.
    export PR_WATCH_SCENARIO=approved
    run bash "$TOOL" 172 --no-request --timeout 5 --interval 1
    assert_success
    assert_output --partial "outcome: review"
}

@test "a commented review that reports no open issues exits 0" {
    export PR_WATCH_SCENARIO=clean_comment
    run bash "$TOOL" 172 --no-request --timeout 5 --interval 1
    assert_success
    assert_output --partial "outcome: review"
}

@test "findings that live only in the review body exit 5" {
    export PR_WATCH_SCENARIO=body_only
    run bash "$TOOL" 172 --no-request --timeout 5 --interval 1
    assert_equal "$status" 5
    assert_output --partial "previously missed"
}

@test "a change request exits 5 even with no threads" {
    export PR_WATCH_SCENARIO=changes
    run bash "$TOOL" 172 --no-request --timeout 5 --interval 1
    assert_equal "$status" 5
}

@test "an acknowledgement with no body and no comments exits 0" {
    export PR_WATCH_SCENARIO=ack
    run bash "$TOOL" 172 --no-request --timeout 5 --interval 1
    assert_success
    assert_output --partial "outcome: review"
}

# ── The merge gate's own edges ───────────────────────────────────────────────

@test "--until green treats a skipped required check as green" {
    export PR_PROTECTION="lint"
    export PR_WATCH_SCENARIO=skipping
    run bash "$TOOL" 172 --until green --timeout 5 --interval 1
    assert_equal "$status" 6
    assert_output --partial "checks: pass"
}

@test "the digest names the merge state so a stale branch is visible" {
    export PR_PROTECTION="build"
    export PR_WATCH_SCENARIO=none
    run bash "$TOOL" 172 --until green --timeout 5 --interval 1
    assert_equal "$status" 6
    assert_output --partial "merge state: CLEAN"

    export PR_MERGE_STATE=BEHIND
    run bash "$TOOL" 172 --until green --timeout 2 --interval 1
    assert_equal "$status" 4
    assert_output --partial "merge state: BEHIND"
}

@test "--until green never calls a draft pull request green" {
    # isDraft is its own field: a draft reads CLEAN and MERGEABLE.
    export PR_WATCH_SCENARIO=none
    export PR_IS_DRAFT=true
    run bash "$TOOL" 172 --until green --timeout 2 --interval 1
    assert_equal "$status" 4
    assert_output --partial "merge state: draft"
}

@test "--until green does not wait for the approval a human owes" {
    export PR_PROTECTION="build"
    # BLOCKED is a missing approval or an unresolved thread — not CI.
    export PR_WATCH_SCENARIO=none
    export PR_MERGE_STATE=BLOCKED
    run bash "$TOOL" 172 --until green --timeout 5 --interval 1
    assert_equal "$status" 6
}

@test "an approval that still carries line comments is not clean" {
    export PR_WATCH_SCENARIO=approved_comments
    run bash "$TOOL" 172 --no-request --timeout 5 --interval 1
    assert_equal "$status" 5
}

@test "a failed comments read is a runtime error, not a clean review" {
    # Treating an unavailable comments endpoint as "no findings" would report a
    # reviewed pull request as clean during an outage.
    export PR_WATCH_SCENARIO=comments_broken
    run bash "$TOOL" 172 --no-request --timeout 5 --interval 1
    assert_equal "$status" 1
    assert_output --partial "ERROR:"
}

@test "--until green never reports a pull request with no required check as green" {
    # gh answers "no required checks reported" when the repo gates on no check.
    # A vacuous gate is not evidence, so the wait runs out instead.
    export PR_WATCH_SCENARIO=unconfigured
    run bash "$TOOL" 172 --until green --timeout 2 --interval 1
    assert_equal "$status" 4
    assert_output --partial "required checks: none reported"
}

@test "the digest separates the gate from the overall check set" {
    export PR_WATCH_SCENARIO=unconfigured
    run bash "$TOOL" 172 --until green --timeout 2 --interval 1
    assert_equal "$status" 4
    assert_output --partial "checks: fail"
    assert_output --partial "required checks: none reported"
}

@test "a body reporting ten open issues is not a clean round" {
    # "0 open issues" as a substring also matches "10 open issues".
    export PR_WATCH_SCENARIO=ten_issues
    run bash "$TOOL" 172 --no-request --timeout 5 --interval 1
    assert_equal "$status" 5
}

@test "an uncomputed merge state keeps waiting instead of going green" {
    export PR_WATCH_SCENARIO=none
    export PR_MERGEABLE=MERGEABLE
    export PR_MERGE_STATE=""
    run bash "$TOOL" 172 --until green --timeout 2 --interval 1
    assert_equal "$status" 4
}

@test "a failed required-check query is a runtime error, not a fallback" {
    # Falling back to the overall set here would call optional checks required.
    export PR_WATCH_SCENARIO=none
    export PR_WATCH_REQUIRED=broken_query
    run bash "$TOOL" 172 --until green --timeout 2 --interval 1
    assert_equal "$status" 1
    assert_output --partial "ERROR:"
}

@test "json keeps the status field it reported before" {
    export PR_WATCH_SCENARIO=review
    run bash "$TOOL" 172 --no-request --timeout 5 --interval 1 --json
    assert_equal "$status" 5
    assert_output --partial '"state": "review-failed"'
    assert_output --partial '"status": "review-failed"'
}

@test "a red check outside the gate is not listed as a failure" {
    export PR_PROTECTION="build"
    # "Failing checks" beside an all-green outcome reads as a contradiction.
    export PR_WATCH_SCENARIO=optional_fail
    run bash "$TOOL" 172 --until green --timeout 5 --interval 1
    assert_equal "$status" 6
    assert_output --partial "Failing optional checks"
    refute_output --partial "### Failing checks"
}

@test "--until green does not go green before any check has reported" {
    # A fresh push has no check runs for a moment; gh cannot say what is
    # required yet, and that is not evidence the gate is satisfied.
    export PR_WATCH_SCENARIO=nochecks
    run bash "$TOOL" 172 --until green --timeout 2 --interval 1
    assert_equal "$status" 4
}

@test "--until green waits while a check is still pending" {
    export PR_WATCH_SCENARIO=pending
    export PR_WATCH_REQUIRED=unconfigured
    run bash "$TOOL" 172 --until green --timeout 2 --interval 1
    assert_equal "$status" 4
}

@test "a dismissed review does not count as a clean round" {
    # A dismissed review is not a verdict on the current head, whatever its body.
    export PR_WATCH_SCENARIO=dismissed
    run bash "$TOOL" 172 --no-request --timeout 2 --interval 1
    assert_equal "$status" 4
}

@test "an unparseable required-check response is a runtime error" {
    # Silent fallback would make optional checks stand in for the merge gate.
    export PR_WATCH_SCENARIO=none
    export PR_WATCH_REQUIRED=garbage
    run bash "$TOOL" 172 --until green --timeout 2 --interval 1
    assert_equal "$status" 1
    assert_output --partial "ERROR:"
}

@test "--until green does not read an unknown gate as a passed one" {
    # A silent --required answer must not let the overall set stand in: that is
    # how optional checks become the merge gate.
    export PR_WATCH_SCENARIO=none
    export PR_WATCH_REQUIRED=silent
    run bash "$TOOL" 172 --until green --timeout 2 --interval 1
    assert_equal "$status" 4
}

@test "an unknown gate does not make an optional failure blocking" {
    # Exit 3 comes from the required set alone; with no answer from gh there is
    # no required set to fail.
    export PR_WATCH_SCENARIO=optional_fail
    export PR_WATCH_REQUIRED=silent
    run bash "$TOOL" 172 --no-request --timeout 2 --interval 1
    assert_equal "$status" 4
}

@test "an empty required-check array is not a passed gate" {
    export PR_WATCH_SCENARIO=none
    export PR_WATCH_REQUIRED=empty
    run bash "$TOOL" 172 --until green --timeout 2 --interval 1
    assert_equal "$status" 4
}

@test "an approval whose body reports open issues is not clean" {
    # The review's own counts outrank its state.
    export PR_WATCH_SCENARIO=approved_issues
    run bash "$TOOL" 172 --no-request --timeout 5 --interval 1
    assert_equal "$status" 5
}

@test "a singular open-issue heading is read as a finding" {
    # Copilot writes "1 open issue", not "1 open issues".
    export PR_WATCH_SCENARIO=approved_single
    run bash "$TOOL" 172 --no-request --timeout 5 --interval 1
    assert_equal "$status" 5
}

@test "json keeps the pre-rename spelling of status" {
    # status existed before this change; checks_failed is what it said then.
    export PR_WATCH_SCENARIO=none
    export PR_WATCH_REQUIRED=fail
    run bash "$TOOL" 172 --no-request --timeout 5 --interval 1 --json
    assert_equal "$status" 3
    assert_output --partial '"state": "check-failed"'
    assert_output --partial '"status": "checks_failed"'
}

# ── The declared gate: --required cannot see a check that has not started ────

@test "--until green waits for a declared required check that has not started" {
    # gh pr checks --required lists only contexts that exist, so a required
    # check still queued is invisible there; the declaration is the answer.
    export PR_WATCH_SCENARIO=lint_only
    export PR_PROTECTION="lint test"
    run bash "$TOOL" 172 --until green --timeout 2 --interval 1
    assert_equal "$status" 4
}

@test "--until green returns 6 once every declared check is green" {
    export PR_WATCH_SCENARIO=lint_test
    export PR_PROTECTION="lint test"
    run bash "$TOOL" 172 --until green --timeout 5 --interval 1
    assert_equal "$status" 6
}

@test "--until green reports a failed declared check as 3" {
    export PR_WATCH_SCENARIO=lint_fail
    export PR_PROTECTION="lint test"
    run bash "$TOOL" 172 --until green --timeout 5 --interval 1
    assert_equal "$status" 3
    assert_output --partial "lint"
}

@test "--until green never goes green when the declaration is unreadable" {
    # No protection and no rulesets: nothing proves what is required.
    export PR_WATCH_SCENARIO=lint_test
    run bash "$TOOL" 172 --until green --timeout 2 --interval 1
    assert_equal "$status" 4
}

@test "a ruleset that applies to this branch is part of the gate" {
    export PR_WATCH_SCENARIO=lint_test
    export PR_PROTECTION="lint test"
    export PR_RULESETS="1=deploy"
    run bash "$TOOL" 172 --until green --timeout 2 --interval 1
    assert_equal "$status" 4
}

@test "a ruleset scoped to another branch is not the gate" {
    export PR_WATCH_SCENARIO=lint_test
    export PR_PROTECTION="lint test"
    export PR_RULESETS="1=deploy"
    export PR_RULESET_REF="refs/heads/release/*"
    run bash "$TOOL" 172 --until green --timeout 5 --interval 1
    assert_equal "$status" 6
}

@test "an unreadable ruleset listing never reports green" {
    export PR_WATCH_SCENARIO=lint_test
    export PR_PROTECTION="lint test"
    export PR_RULESET_FAIL=1
    run bash "$TOOL" 172 --until green --timeout 2 --interval 1
    assert_equal "$status" 4
}

@test "an exempt declared check that has not started does not block the gate" {
    export PR_WATCH_SCENARIO=lint_only
    export PR_PROTECTION="lint no-fixup"
    run bash "$TOOL" 172 --until green --timeout 5 --interval 1
    assert_equal "$status" 6
}

@test "a ruleset scoped with ~DEFAULT_BRANCH applies to the base branch" {
    export PR_WATCH_SCENARIO=lint_test
    export PR_PROTECTION="lint test"
    export PR_RULESETS="1=deploy"
    export PR_RULESET_REF="~DEFAULT_BRANCH"
    run bash "$TOOL" 172 --until green --timeout 2 --interval 1
    assert_equal "$status" 4
}

@test "a ruleset scoped with ~ALL applies to the base branch" {
    export PR_WATCH_SCENARIO=lint_test
    export PR_PROTECTION="lint test"
    export PR_RULESETS="1=deploy"
    export PR_RULESET_REF="~ALL"
    run bash "$TOOL" 172 --until green --timeout 2 --interval 1
    assert_equal "$status" 4
}

@test "the default branch is read from the pull request's repository" {
    # --repo may point at another checkout's repository; ~DEFAULT_BRANCH must
    # then resolve there, not here.
    export PR_WATCH_SCENARIO=lint_test
    export PR_PROTECTION="lint test"
    run bash "$TOOL" GET-E/dev-bot#172 --until green --timeout 5 --interval 1
    assert_equal "$status" 6
    assert [ -f "$BATS_TEST_TMPDIR/repoarg" ]
    run cat "$BATS_TEST_TMPDIR/repoarg"
    assert_output --partial "repo view GET-E/dev-bot"
}
