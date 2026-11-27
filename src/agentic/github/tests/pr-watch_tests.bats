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
  "repo view"*) echo "GET-E/dev-bot" ;;
  "api users/"*)
      if [ -n "${PR_WATCH_BOT_BROKEN:-}" ]; then echo "boom" >&2; exit 1; fi
      echo "BOT_NODE_ID" ;;
  "api --paginate"*"timeline"*)
      [ -f "@MARKER@" ] && echo "2026-01-01T00:00:00Z" ;;

  "pr view"*"--json commits"*) echo "2025-12-31T00:00:00Z" ;;
  "pr view"*)
      printf '{"number":172,"state":"OPEN","isDraft":false,"reviewDecision":"%s","headRefName":"feat/x","title":"test pr","url":"https://example/pr/172"}\n' "${PR_REVIEW_DECISION:-}"
      ;;
  "api graphql"*)
      touch "@MARKER@"
      echo '{"data":{"requestReviews":{"clientMutationId":null}}}'
      ;;
  "api "*"/pulls/"*"/comments"*)
      if [ "$scenario" = comments ]; then echo "9001"; fi ;;
  "api "*"/reviews"*)
      if [ "$scenario" = review ]; then
          echo '{"id":77,"user":"copilot-pull-request-reviewer[bot]","state":"COMMENTED","submitted_at":"2026-01-01T00:00:00Z","body":"Found a null deref in the retry loop."}'
      elif [ "$scenario" = comments ]; then
          echo '{"id":78,"user":"copilot-pull-request-reviewer[bot]","state":"COMMENTED","submitted_at":"2026-01-01T00:00:00Z","body":""}'
      fi
      ;;
  "pr checks"*"--required"*)
      case "${PR_WATCH_REQUIRED:-$scenario}" in
        fail) echo '[{"name":"build","state":"FAILURE","bucket":"fail"}]' ;;
        fixup) echo '[{"name":"no-fixup","state":"FAILURE","bucket":"fail"}]' ;;
        fixup_ok) echo '[{"name":"no-fixup","state":"SUCCESS","bucket":"pass"}]' ;;
        fixup2) echo '[{"name":"No fixup! commits","state":"FAILURE","bucket":"fail"}]' ;;
        other) echo '[{"name":"deploy-check","state":"FAILURE","bucket":"fail"}]' ;;
        none|nochecks) exit 1 ;;
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
      if [ "$scenario" = fail ]; then
          echo '[{"name":"build","state":"FAILURE","bucket":"fail"}]'
      else
          echo '[{"name":"build","state":"SUCCESS","bucket":"pass"}]'
      fi
      ;;
  *) echo "unexpected gh call: $*" >&2; exit 1 ;;
esac
STUB
    chmod +x "$STUBS/gh"
    sed -i "s|@MARKER@|$BATS_TEST_TMPDIR/requested|g" "$STUBS/gh"
    export PATH="$STUBS:$PATH"
}

@test "mcp-meta describes the tool" {
    run bash "$TOOL" mcp-meta
    assert_success
    assert_output --partial '"name":"pr-watch"'
    assert_output --partial "Exit codes carry the outcome"
}

@test "a review with findings exits 0 and prints the digest" {
    export PR_WATCH_SCENARIO=review
    run bash "$TOOL" 172 --no-request --timeout 5 --interval 1
    assert_success
    assert_output --partial "PR #172"
    assert_output --partial "Latest review"
    assert_output --partial "null deref"
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
    assert_success
    assert_output --partial '"status": "review"'
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

@test "a final review decision stops polling with no review body" {
    export PR_WATCH_SCENARIO=none
    export PR_REVIEW_DECISION=APPROVED
    run bash "$TOOL" 172 --no-request --timeout 30 --interval 1
    assert_success
    assert_output --partial "APPROVED"
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
    assert_success
    assert_output --partial "PR #172"

    run bash "$TOOL" "#172" --no-request --timeout 5 --interval 1
    assert_success

    run bash "$TOOL" "GET-E/dev-bot#172" --no-request --timeout 5 --interval 1
    assert_success
}

@test "a review whose findings are only line comments still exits 0" {
    export PR_WATCH_SCENARIO=comments
    run bash "$TOOL" 172 --no-request --timeout 30 --interval 1
    assert_success
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

@test "a fixup guard does not exit 3 when gh cannot list the required set" {
    export PR_WATCH_SCENARIO=guard_overall
    export PR_WATCH_REQUIRED=none
    run bash "$TOOL" 172 --no-request --timeout 1 --interval 1
    assert_equal "$status" 4
    assert_output --partial "Ignored checks"
    assert_output --partial "no-fixup"
}

@test "an ignored guard is named even when the review landed first" {
    export PR_WATCH_SCENARIO=review
    export PR_WATCH_REQUIRED=fixup
    run bash "$TOOL" 172 --no-request --timeout 5 --interval 1 --json
    assert_success
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
