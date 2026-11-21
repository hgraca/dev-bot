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
  "api users/"*) echo "BOT_NODE_ID" ;;
  "api --paginate"*"timeline"*)
      [ -f "@MARKER@" ] && echo "2026-01-01T00:00:00Z" ;;

  "pr view"*) echo '{"number":172,"state":"OPEN","isDraft":false,"reviewDecision":"","headRefName":"feat/x","title":"test pr","url":"https://example/pr/172"}' ;;
  "api graphql"*)
      touch "@MARKER@"
      echo '{"data":{"requestReviews":{"clientMutationId":null}}}'
      ;;
  "api "*"/reviews"*)
      if [ "$scenario" = review ]; then
          echo '{"user":"copilot-pull-request-reviewer[bot]","state":"COMMENTED","submitted_at":"2026-01-01T00:00:00Z","body":"Found a null deref in the retry loop."}'
      fi
      ;;
  "pr checks"*)
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

@test "a non-numeric PR number is a usage error" {
    run bash "$TOOL" not-a-number
    assert_equal "$status" 2
    assert_output --partial "must be digits"
}

@test "json output carries the outcome" {
    export PR_WATCH_SCENARIO=review
    run bash "$TOOL" 172 --no-request --timeout 5 --interval 1 --json
    assert_success
    assert_output --partial '"status": "review"'
    assert_output --partial '"repository": "GET-E/dev-bot"'
}
