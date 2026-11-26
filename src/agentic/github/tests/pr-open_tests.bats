#!/usr/bin/env bats
# =============================================================================
# src/agentic/github/tests/pr-open_tests.bats
# Guards the one-call contract: push, create, assign, request; nothing repeats
# when the PR or the assignment already exists; a failed assignment or review is
# reported without losing the PR; and a bad body file stops before the remote.
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
  "pr view"*"--json commits"*) echo "2025-12-31T00:00:00Z" ;;
  "pr view"*"--json id"*) echo "PR_NODE_ID" ;;
  "pr view"*"--json assignees"*) [ -n "\${ASSIGNED:-}" ] && echo "\${ASSIGNED}" ;;
  "pr edit"*)
      [ -n "\${ASSIGN_FAIL:-}" ] && { echo "boom" >&2; exit 1; }
      exit 0
      ;;
  "repo view"*) echo "GET-E/dev-bot" ;;
  "api user --jq .login") echo "octocat" ;;
  "api users/"*) echo "BOT_NODE_ID" ;;
  "api --paginate"*"timeline"*)
      [ -n "\${REVIEW_NEVER:-}" ] && exit 0
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
    assert_output --partial '--assignee <login>'
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

@test "no --assignee leaves the PR unassigned" {
    run bash "$TOOL" --title "t" --body-file "$BODY" --no-review
    assert_success
    assert_output --partial '"assignee": "skipped"'
    run cat "$CALLS"
    refute_output --partial "pr edit"
}

@test "it assigns after creating and before requesting the review" {
    run bash "$TOOL" --title "t" --body-file "$BODY" --assignee @me
    assert_success
    assert_output --partial '"assignee": "assigned"'
    run cat "$CALLS"
    assert_output --partial "gh pr edit https://example/pr/42 --add-assignee @me"
    create_line="$(grep -n 'gh pr create' "$CALLS" | head -1 | cut -d: -f1)"
    assign_line="$(grep -n 'gh pr edit' "$CALLS" | head -1 | cut -d: -f1)"
    review_line="$(grep -n 'api graphql' "$CALLS" | head -1 | cut -d: -f1)"
    [ "$create_line" -lt "$assign_line" ]
    [ "$assign_line" -lt "$review_line" ]
}

@test "an assignee already on the PR is not added twice" {
    export ASSIGNED=octocat
    run bash "$TOOL" --title "t" --body-file "$BODY" --assignee @me --no-review
    assert_success
    assert_output --partial '"assignee": "already assigned"'
    run cat "$CALLS"
    refute_output --partial "pr edit"
}

@test "an assignee that fails still leaves the PR, reported at the end" {
    export ASSIGN_FAIL=1
    run bash "$TOOL" --title "t" --body-file "$BODY" --assignee @me
    assert_equal "$status" 1
    assert_output --partial 'https://example/pr/42'
    assert_output --partial '"assignee": "failed (boom)"'
    assert_output --partial "the assignee was not added"
    run cat "$CALLS"
    assert_output --partial "api graphql"
}

@test "a failed assignee and a failed review are both reported" {
    export ASSIGN_FAIL=1 REVIEW_NEVER=1
    run bash "$TOOL" --title "t" --body-file "$BODY" --assignee @me
    assert_equal "$status" 1
    assert_output --partial 'https://example/pr/42'
    assert_output --partial '"assignee": "failed (boom)"'
    assert_output --partial '"review": "not queued"'
    assert_output --partial "the assignee was not added"
    assert_output --partial "the Copilot review did not register"
    [ "$(printf '%s\n' "$output" | grep -c '^ERROR:')" -eq 2 ]
}

@test "an empty body file is refused before anything is pushed" {
    : >"$BATS_TEST_TMPDIR/empty.md"
    run bash "$TOOL" --title "t" --body-file "$BATS_TEST_TMPDIR/empty.md"
    assert_equal "$status" 2
    assert_output --partial "body file is empty"
    [ ! -s "$CALLS" ]
}

@test "a review request that does not register exits 1 but still prints the URL" {
    export REVIEW_NEVER=1
    run bash "$TOOL" --title "t" --body-file "$BODY"
    assert_equal "$status" 1
    assert_output --partial 'https://example/pr/42'
    assert_output --partial "did not register"
}
