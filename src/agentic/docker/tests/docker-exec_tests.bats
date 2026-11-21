#!/usr/bin/env bats
# =============================================================================
# src/agentic/docker/tests/docker-exec_tests.bats
# Guards target resolution: a named service wins, the only running container is
# picked, ambiguity refuses instead of guessing. docker is stubbed, so nothing
# reaches a daemon.
# =============================================================================

setup() {
    bats_load_library bats-support
    bats_load_library bats-assert

    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
    TOOL="$MODULE_DIR/tools/docker-exec.mcp.sh"

    STUBS="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$STUBS"
    RECORD="$BATS_TEST_TMPDIR/docker-args"
    cat >"$STUBS/docker" <<STUB
#!/usr/bin/env bash
printf '%s\\n' "\$@" >>"$RECORD"
case "\$*" in
  "compose ps"*) printf '%s\\n' "\${DOCKER_PS_ROWS:-}" ;;
  "exec "*) exit 0 ;;
  *) exit 0 ;;
esac
STUB
    chmod +x "$STUBS/docker"
    export PATH="$STUBS:$PATH"
}

@test "mcp-meta describes the tool" {
    run bash "$TOOL" mcp-meta
    assert_success
    assert_output --partial '"name":"docker-exec"'
    assert_output --partial 'without naming it'
}

@test "a single running container is picked without --service" {
    export DOCKER_PS_ROWS='{"Name":"transfers-app-1","Service":"app","State":"running"}'
    run bash "$TOOL" php -v
    assert_success
    run cat "$RECORD"
    assert_output --partial "exec"
    assert_output --partial "transfers-app-1"
    assert_output --partial "php"
}

@test "--service selects among several containers" {
    export DOCKER_PS_ROWS='{"Name":"proj-app-1","Service":"app","State":"running"}
{"Name":"proj-db-1","Service":"db","State":"running"}'
    run bash "$TOOL" --service db mysql -e "select 1"
    assert_success
    run cat "$RECORD"
    assert_output --partial "proj-db-1"
    refute_output --partial "proj-app-1"
}

@test "several candidates without --service refuse instead of guessing" {
    export DOCKER_PS_ROWS='{"Name":"proj-app-1","Service":"app","State":"running"}
{"Name":"proj-db-1","Service":"db","State":"running"}'
    run bash "$TOOL" php -v
    assert_equal "$status" 3
    assert_output --partial "several containers match"
    assert_output --partial "proj-db-1"
}

@test "an unknown service lists the available ones" {
    export DOCKER_PS_ROWS='{"Name":"proj-app-1","Service":"app","State":"running"}'
    run bash "$TOOL" --service nope php -v
    assert_equal "$status" 3
    assert_output --partial "services: app"
}

@test "--list prints the containers and runs nothing" {
    export DOCKER_PS_ROWS='{"Name":"proj-app-1","Service":"app","State":"running"}'
    run bash "$TOOL" --list
    assert_success
    assert_output --partial "proj-app-1"
    refute_output --partial "exec"
}

@test "no command is a usage error" {
    export DOCKER_PS_ROWS='{"Name":"proj-app-1","Service":"app","State":"running"}'
    run bash "$TOOL"
    assert_equal "$status" 2
    assert_output --partial "no command given"
}
