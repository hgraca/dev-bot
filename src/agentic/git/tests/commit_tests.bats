#!/usr/bin/env bats
# =============================================================================
# src/agentic/git/tests/commit_tests.bats
# Guards the safety contract: only the named paths land, a foreign staged entry
# stays out, the message must exist, and --fixup writes git's own marker.
# =============================================================================

setup() {
    bats_load_library bats-support
    bats_load_library bats-assert

    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
    TOOL="$MODULE_DIR/tools/commit.mcp.sh"

    command -v python3 >/dev/null || skip "python3 not installed"

    REPO="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$REPO"
    git -C "$REPO" init -q --initial-branch=main
    git -C "$REPO" config user.email "test@test.com"
    git -C "$REPO" config user.name "Test"
    git -C "$REPO" config commit.gpgsign false
    echo "one" >"$REPO/one.txt"
    echo "two" >"$REPO/two.txt"
    git -C "$REPO" add -A
    git -C "$REPO" commit -q -m "initial"

    MSG="$BATS_TEST_TMPDIR/msg.txt"
    printf 'test: a message\n\nProblems:\n- a\n\nSolutions:\n- b\n' >"$MSG"
}

@test "mcp-meta describes the tool" {
    run bash "$TOOL" mcp-meta
    assert_success
    assert_output --partial '"name":"commit"'
    assert_output --partial 'never a whole tree'
}

@test "it commits the named path and prints the new commit" {
    echo "changed" >>"$REPO/one.txt"
    run bash "$TOOL" --message-file "$MSG" --cwd "$REPO" one.txt
    assert_success
    assert_output --partial "test: a message"
    git -C "$REPO" log -1 --format=%s | grep -q "test: a message"
}

@test "an unstaged sibling never rides along" {
    echo "changed" >>"$REPO/one.txt"
    echo "sibling" >>"$REPO/two.txt"
    run bash "$TOOL" --message-file "$MSG" --cwd "$REPO" one.txt
    assert_success
    run git -C "$REPO" show --stat --format= HEAD
    assert_output --partial "one.txt"
    refute_output --partial "two.txt"
}

@test "a staged foreign entry stays out of the commit" {
    echo "foreign" >>"$REPO/two.txt"
    git -C "$REPO" add two.txt
    echo "changed" >>"$REPO/one.txt"
    run bash "$TOOL" --message-file "$MSG" --cwd "$REPO" one.txt
    assert_success
    run git -C "$REPO" show --stat --format= HEAD
    refute_output --partial "two.txt"
}

@test "--fixup writes git's marker against the target" {
    echo "changed" >>"$REPO/one.txt"
    target="$(git -C "$REPO" rev-parse --short HEAD)"
    run bash "$TOOL" --fixup "$target" --cwd "$REPO" one.txt
    assert_success
    git -C "$REPO" log -1 --format=%s | grep -q "^fixup!"
}

@test "no message is a usage error" {
    echo "changed" >>"$REPO/one.txt"
    run bash "$TOOL" --cwd "$REPO" one.txt
    assert_equal "$status" 2
    assert_output --partial "exactly one of"
}

@test "an empty message file is a usage error" {
    : >"$BATS_TEST_TMPDIR/empty.txt"
    run bash "$TOOL" --message-file "$BATS_TEST_TMPDIR/empty.txt" --cwd "$REPO" one.txt
    assert_equal "$status" 2
    assert_output --partial "empty"
}

@test "--fixup with -m is refused" {
    run bash "$TOOL" --fixup abc123 -m "x" --cwd "$REPO" one.txt
    assert_equal "$status" 2
    assert_output --partial "--fixup writes its own message"
}

@test "a directory pathspec is refused instead of staging the tree" {
    mkdir -p "$REPO/sub"
    echo "inside" >"$REPO/sub/inner.txt"
    run bash "$TOOL" --message-file "$MSG" --cwd "$REPO" sub
    assert_equal "$status" 2
    assert_output --partial "whole-tree pathspec"
    run git -C "$REPO" log -1 --format=%s
    assert_output "initial"
}

@test "a bare dot is refused" {
    echo "changed" >>"$REPO/one.txt"
    run bash "$TOOL" --message-file "$MSG" --cwd "$REPO" .
    assert_equal "$status" 2
    assert_output --partial "whole-tree pathspec"
}
