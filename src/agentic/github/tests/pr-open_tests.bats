#!/usr/bin/env bats
# =============================================================================
# src/agentic/github/tests/pr-open_tests.bats
# Guards the three-in-one contract: push, create, request; nothing repeats when
# the PR already exists; and a bad body file stops before touching the remote.
# git and gh are stubbed, so no repository and no network are needed.
# =============================================================================

setup() {
    bats_load_library bats-support
    bats_load_library bats-assert

    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
    TOOL="$MODULE_DIR/tools/pr-open.mcp.sh"

    STUBS="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$STUBS"
    CALLS="$BATS_TEST_TMPDIR/calls"
    : >"$CALLS"

    cat >"$STUBS/git" <<GITSTUB
#!/usr/bin/env bash
echo "git \$*" >>"$CALLS"
case "\$*" in
  "branch --show-current") echo "feat/x" ;;
  "rev-parse --verify --quiet origin/feat/x") exit 1 ;;
  "push -u origin feat/x") echo "pushed" ;;
  *) exit 0 ;;
esac
GITSTUB

    cat >"$STUBS/gh" <<GHSTUB
#!/usr/bin/env bash
echo "gh \$*" >>"$CALLS"
case "\$*" in
  "pr list"*) [ "\${PR_OPEN:-0}" = "1" ] && echo "https://example/pr/42" || echo "" ;;
  "pr create"*) echo "https://example/pr/42" ;;
  "pr view"*"--json number"*) echo "42" ;;
  "pr view"*"--json id"*) echo "PR_NODE_ID" ;;
  "repo view"*) echo "GET-E/dev-bot" ;;
  "api users/"*) echo "BOT_NODE_ID" ;;
  "api --paginate"*"timeline"*)
      [ -f "@MARKER@" ] && echo "2026-01-01T00:00:00Z" ;;
  "api graphql"*)
      touch "@MARKER@"
      echo '{"data":{"requestReviews":{"clientMutationId":null}}}'
      ;;
  *) exit 0 ;;
esac
GHSTUB

    chmod +x "$STUBS/git" "$STUBS/gh"
    sed -i "s|@MARKER@|$BATS_TEST_TMPDIR/requested|g" "$STUBS/gh"
    export PATH="$STUBS:$PATH"

    BODY="$BATS_TEST_TMPDIR/body.md"
    printf 'A body.\n' >"$BODY"
}

@test "mcp-meta describes the tool" {
    run bash "$TOOL" mcp-meta
    assert_success
    assert_output --partial '"name":"pr-open"'
    assert_output --partial 'request the Copilot review'
}

@test "it pushes, opens and requests the review" {
    run bash "$TOOL" --title "feat(x): a thing" --body-file "$BODY"
    assert_success
    assert_output --partial '"pr": "opened"'
    assert_output --partial 'https://example/pr/42'
    assert_output --partial '"review": "requested"'
    run cat "$CALLS"
    assert_output --partial "git push -u origin feat/x"
    assert_output --partial "gh pr create"
}

@test "an already open PR is reused, not recreated" {
    export PR_OPEN=1
    run bash "$TOOL" --title "feat(x): a thing" --body-file "$BODY"
    assert_success
    assert_output --partial '"pr": "already open"'
    run cat "$CALLS"
    refute_output --partial "gh pr create"
}

@test "--no-review skips the request" {
    run bash "$TOOL" --title "t" --body-file "$BODY" --no-review
    assert_success
    assert_output --partial '"review": "skipped"'
    run cat "$CALLS"
    refute_output --partial "requested_reviewers"
}

@test "an empty body file is refused before anything is pushed" {
    : >"$BATS_TEST_TMPDIR/empty.md"
    run bash "$TOOL" --title "t" --body-file "$BATS_TEST_TMPDIR/empty.md"
    assert_equal "$status" 2
    assert_output --partial "body file is empty"
    [ ! -s "$CALLS" ]
}
