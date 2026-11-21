#!/usr/bin/env bats
# =============================================================================
# src/agentic/devbot/tests/where_tests.bats
# Guards the single-call contract: the resolver's config is passed through, the
# memory directory and active files are derived from it, and a bad path stops
# before the resolver runs. The resolver is stubbed through PROJECT_FOR_PATH.
# =============================================================================

setup() {
    bats_load_library bats-support
    bats_load_library bats-assert

    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
    TOOL="$MODULE_DIR/tools/where.mcp.sh"

    command -v python3 >/dev/null || skip "python3 not installed"

    PROJECT="$BATS_TEST_TMPDIR/child"
    mkdir -p "$PROJECT/.agents/memory/active/modules"
    printf '# a\n' >"$PROJECT/.agents/memory/active/memory.md"
    printf '# b\n' >"$PROJECT/.agents/memory/active/modules/k8s.md"

    RESOLVER="$BATS_TEST_TMPDIR/resolver.sh"
    cat >"$RESOLVER" <<STUB
#!/usr/bin/env bash
case "\$1" in
  "$PROJECT")
    cat <<JSON
{"name":"child-project","path":"$PROJECT","registered":true,"type":"repo",
 "config":{"commit_memory":"true","workflow":"worktrees","devbot_dir":".agents",
           "datasources":["mariadb"]}}
JSON
    ;;
  *)
    echo "ERROR: path belongs to no registered project: \$1" >&2
    exit 3
    ;;
esac
STUB
    chmod +x "$RESOLVER"
    export PROJECT_FOR_PATH="$RESOLVER"
}

@test "mcp-meta describes the tool" {
    run bash "$TOOL" mcp-meta
    assert_success
    assert_output --partial '"name":"where"'
    assert_output --partial 'Resolve the project context in one call'
}

@test "it reports the project, its config and the memory files" {
    run bash "$TOOL" "$PROJECT"
    assert_success
    assert_output --partial '"project": "child-project"'
    assert_output --partial '"workflow": "worktrees"'
    assert_output --partial '"commit_memory": "true"'
    assert_output --partial '"mariadb"'
    assert_output --partial "memory.md"
    assert_output --partial "modules/k8s.md"
}

@test "a path outside every registered project fails with the resolver's code" {
    mkdir -p "$BATS_TEST_TMPDIR/unregistered"
    run bash "$TOOL" "$BATS_TEST_TMPDIR/unregistered"
    assert_equal "$status" 1
    assert_output --partial "project-for-path failed"
}

@test "a missing path is a usage error before the resolver runs" {
    run bash "$TOOL" "$BATS_TEST_TMPDIR/nope"
    assert_equal "$status" 2
    assert_output --partial "does not exist"
}
