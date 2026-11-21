#!/usr/bin/env bats
# =============================================================================
# src/agentic/k8s/tests/kctl-get_tests.bats
# Guards the argument mapping: no cluster means the project kubeconfig, a cluster
# means the catalogue-scoped form, and the query is passed through untouched.
# kctl is stubbed through KCTL_BIN, so nothing reaches a real cluster and no
# kubectl binary is ever invoked.
# =============================================================================

setup() {
    bats_load_library bats-support
    bats_load_library bats-assert

    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
    TOOL="$MODULE_DIR/tools/kctl-get.mcp.sh"

    RECORD="$BATS_TEST_TMPDIR/kctl-args"
    STUB="$BATS_TEST_TMPDIR/kctl.sh"
    cat >"$STUB" <<STUBKCTL
#!/usr/bin/env bash
printf '%s\\n' "\$@" >"$RECORD"
STUBKCTL
    chmod +x "$STUB"
    export KCTL_BIN="$STUB"
}

@test "mcp-meta describes the tool" {
    run bash "$TOOL" mcp-meta
    assert_success
    assert_output --partial '"name":"kctl-get"'
    assert_output --partial 'without retyping the cluster path'
}

@test "help states the authorisation and the no-prefix rule" {
    run bash "$TOOL" --help
    assert_success
    assert_output --partial "authorised by the"
    assert_output --partial "do NOT prefix"
}

@test "without --cluster it runs the project kubeconfig" {
    run bash "$TOOL" get deploy -n transfers-qa
    assert_success
    run cat "$RECORD"
    assert_line --index 0 "run"
    assert_line --index 1 "."
    assert_line --index 2 -- "--"
    assert_line --index 3 "get"
    assert_line --index 4 "deploy"
}

@test "with --cluster it uses the catalogue-scoped form" {
    run bash "$TOOL" --cluster gete-dev get pods -n transfers-qa
    assert_success
    run cat "$RECORD"
    assert_line --index 0 "exec"
    assert_line --index 1 "gete-dev"
    assert_line --index 2 "."
}

@test "--path is passed to kctl" {
    run bash "$TOOL" --path /srv/project get ns default
    assert_success
    run cat "$RECORD"
    assert_line --index 1 "/srv/project"
}

@test "a missing query is a usage error, not a kubectl call" {
    run bash "$TOOL"
    assert_equal "$status" 2
    assert_output --partial "no query given"
    [ ! -s "$RECORD" ]
}

@test "--cluster without a value is a usage error" {
    run bash "$TOOL" --cluster
    assert_equal "$status" 2
    assert_output --partial "--cluster needs a value"
}
