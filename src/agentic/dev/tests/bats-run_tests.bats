#!/usr/bin/env bats
# =============================================================================
# src/agentic/dev/tests/bats-run_tests.bats
# Guards bats-run's contract: failures only by default, the summary counts, and
# the exit codes a caller branches on. bats is stubbed, so this suite cannot
# recurse into the real runner.
# =============================================================================

setup() {
    bats_load_library bats-support
    bats_load_library bats-assert

    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
    TOOL="$MODULE_DIR/tools/bats-run.mcp.sh"

    STUBS="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$STUBS"
    cat >"$STUBS/bats" <<'STUB'
#!/usr/bin/env bash
# Prints a two-test TAP run, the second one failing.
cat <<'TAP'
1..2
ok 1 a passing test
not ok 2 a failing test
# (in test file example_tests.bats, line 12)
#   `false' failed
#   assert_success failed
TAP
exit 1
STUB
    chmod +x "$STUBS/bats"
    export PATH="$STUBS:$PATH"

    SUITE="$BATS_TEST_TMPDIR/example_tests.bats"
    : >"$SUITE"
}

@test "mcp-meta describes the tool" {
    run bash "$TOOL" mcp-meta
    assert_success
    assert_output --partial '"name":"bats-run"'
    assert_output --partial 'print only the failures'
}

@test "failures are printed with their diagnostics and passing tests are not" {
    run bash "$TOOL" "$SUITE"
    assert_equal "$status" 1
    assert_output --partial "not ok 2 a failing test"
    assert_output --partial "assert_success failed"
    assert_output --partial "1 passed, 1 failed"
    refute_output --partial "ok 1 a passing test"
}

@test "--verbose keeps the passing tests" {
    run bash "$TOOL" "$SUITE" --verbose
    assert_equal "$status" 1
    assert_output --partial "ok 1 a passing test"
}

@test "no suite files is a usage error" {
    run bash "$TOOL"
    assert_equal "$status" 2
    assert_output --partial "no suite files given"
}

@test "a missing suite file is a usage error" {
    run bash "$TOOL" "$BATS_TEST_TMPDIR/nope.bats"
    assert_equal "$status" 2
    assert_output --partial "suite file not found"
}

@test "an unknown flag is a usage error" {
    run bash "$TOOL" "$SUITE" --frobnicate
    assert_equal "$status" 2
    assert_output --partial "unknown flag"
}
