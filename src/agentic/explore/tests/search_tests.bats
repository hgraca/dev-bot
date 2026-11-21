#!/usr/bin/env bats
# =============================================================================
# src/agentic/explore/tests/search_tests.bats
# Guards the digest contract: excluded trees never appear, the per-file counts
# are right, and the exit codes distinguish "no matches" from a usage error.
# =============================================================================

setup() {
    bats_load_library bats-support
    bats_load_library bats-assert

    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
    TOOL="$MODULE_DIR/tools/search.mcp.sh"

    command -v rg >/dev/null || skip "ripgrep not installed"

    REPO="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$REPO/src" "$REPO/node_modules/dep" "$REPO/vendor"
    printf 'needle one\nother\nneedle two\n' >"$REPO/src/a.txt"
    printf 'needle three\n' >"$REPO/src/b.txt"
    printf 'needle in a dependency\n' >"$REPO/node_modules/dep/x.js"
    printf 'needle in vendor\n' >"$REPO/vendor/v.php"
}

@test "mcp-meta describes the tool" {
    run bash "$TOOL" mcp-meta
    assert_success
    assert_output --partial '"name":"search"'
    assert_output --partial 'digest instead of raw ripgrep output'
}

@test "the digest counts matches per file and excludes dependencies" {
    run bash "$TOOL" needle --path "$REPO"
    assert_success
    assert_output --partial "3 match(es) in 2 file(s)"
    assert_output --partial "src/a.txt"
    assert_output --partial "(2)"
    refute_output --partial "node_modules"
    refute_output --partial "vendor"
}

@test "no matches exits 1 and says so on stderr" {
    run bash "$TOOL" definitely-not-present --path "$REPO"
    assert_equal "$status" 1
    assert_output --partial "no matches"
}

@test "an excluded tree can be included with --no-default-excludes" {
    run bash "$TOOL" needle --path "$REPO" --no-default-excludes
    assert_success
    assert_output --partial "node_modules"
}

@test "a bad limit is a usage error" {
    run bash "$TOOL" needle --path "$REPO" --max-per-file 0
    assert_equal "$status" 2
    assert_output --partial "must be positive"
}
