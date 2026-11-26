#!/usr/bin/env bats
# =============================================================================
# src/agentic/github/tests/deploy-wait_tests.bats
# Guards deploy-wait's contract: the metadata the MCP farm reads, the exit
# codes that carry the outcome, the run it selects out of a list, and the digest
# a caller relies on. gh is stubbed, so no network and no authentication are
# needed.
# =============================================================================

setup() {
    bats_load_library bats-support
    bats_load_library bats-assert

    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
    TOOL="$MODULE_DIR/tools/deploy-wait.mcp.sh"

    STUBS="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$STUBS"
    cat >"$STUBS/gh" <<'STUB'
#!/usr/bin/env bash
# Scenario is chosen by DEPLOY_WAIT_SCENARIO; counters live under DEPLOY_WAIT_STATE.
scenario="${DEPLOY_WAIT_SCENARIO:-success}"
state="${DEPLOY_WAIT_STATE:-/tmp}"
bump() {
    local file="$state/count-$1" n=0
    [ -f "$file" ] && n="$(cat "$file")"
    n=$((n + 1))
    printf '%s' "$n" >"$file"
    printf '%s' "$n"
}

run_json() { # id status conclusion sha createdAt
    printf '{"databaseId":%s,"status":"%s","conclusion":"%s","workflowName":"Deploy staging","headBranch":"main","headSha":"%s","event":"workflow_dispatch","createdAt":"%s","startedAt":"%s","updatedAt":"2026-01-01T00:05:00Z","url":"https://github.com/%s/actions/runs/%s","displayTitle":"Deploy staging"}' \
        "$1" "$2" "$3" "$4" "$5" "$5" "${REPO:-GET-E/dev-bot}" "$1"
}

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# A run completed before deploy-wait was ever called — it is not this deploy.
STALE="$(run_json 901 completed success aaaa111122223333 2020-01-01T00:00:00Z)"

if [ "${1:-}" = "repo" ]; then
    if [ "${DEPLOY_WAIT_NO_REPO_VIEW:-}" = "1" ]; then
        echo "no local repo" >&2
        exit 1
    fi
    echo "GET-E/dev-bot"
    exit 0
fi

if [ "${1:-}" = "api" ]; then
    case "$*" in
        */commits/*)
            if [ "${DEPLOY_WAIT_TIP_FAIL:-}" = "1" ]; then
                echo "cannot resolve" >&2
                exit 1
            fi
            ref="${2##*/}"
            case "$ref" in
                # A commit prefix resolves to a full SHA; a branch to its tip.
                *[!0-9a-f]*) echo "${DEPLOY_WAIT_TIP:-aaaa111122223333}" ;;
                *) echo "${ref}55556666" ;;
            esac
            ;;
        *)
            echo "unexpected api call: $*" >&2
            exit 1
            ;;
    esac
    exit 0
fi

if [ "${1:-}" = "run" ] && [ "${2:-}" = "view" ]; then
    previous=""
    for arg in "$@"; do
        if [ "$previous" = "--repo" ]; then REPO="$arg"; fi
        previous="$arg"
    done
    for arg in "$@"; do
        if [ "$arg" = "jobs" ]; then
            echo '{"jobs":[{"name":"build","conclusion":"success"},{"name":"deploy","conclusion":"failure"}]}'
            exit 0
        fi
    done
    case "$scenario" in
        broken)
            echo "boom" >&2
            exit 5
            ;;
        slow)
            sleep 5
            run_json 901 completed success aaaa111122223333 2020-01-01T00:00:00Z
            ;;
        in_progress)
            run_json 901 in_progress "" aaaa111122223333 2020-01-01T00:00:00Z
            ;;
        finish)
            if [ "$(bump view)" -lt 2 ]; then
                run_json 901 in_progress "" aaaa111122223333 2020-01-01T00:00:00Z
            else
                run_json 901 completed success aaaa111122223333 2020-01-01T00:00:00Z
            fi
            ;;
        failure)
            run_json 901 completed failure aaaa111122223333 2020-01-01T00:00:00Z
            ;;
        cancelled)
            run_json 901 completed cancelled aaaa111122223333 2020-01-01T00:00:00Z
            ;;
        commit|commit_none)
            if [ "$3" = "901" ]; then
                run_json 901 completed success bbbb444455556666 2020-01-01T00:00:00Z
            else
                run_json 902 completed success aaaa111122223333 2020-01-01T00:00:00Z
            fi
            ;;
        appear|stale_then_new)
            if [ "$3" = "902" ]; then
                run_json 902 completed success bbbb444455556666 2020-01-01T00:00:00Z
            else
                run_json 901 completed success aaaa111122223333 2020-01-01T00:00:00Z
            fi
            ;;
        tip_bound)
            run_json "$3" completed success aaaa111122223333 2020-01-01T00:00:00Z
            ;;
        rerun)
            if [ "$3" = "902" ]; then
                run_json 902 completed success aaaa111122223333 "$(now_iso)"
            else
                run_json 901 completed success aaaa111122223333 2020-01-01T00:00:00Z
            fi
            ;;
        pending_prior)
            if [ "$3" = "902" ]; then
                run_json 902 completed success aaaa111122223333 "$(now_iso)"
            else
                run_json 900 in_progress "" aaaa111122223333 2020-01-01T00:00:00Z
            fi
            ;;
        *)
            run_json 901 completed success aaaa111122223333 2020-01-01T00:00:00Z
            ;;
    esac
    exit 0
fi

if [ "${1:-}" = "run" ] && [ "${2:-}" = "list" ]; then
    printf '%s\n' "$*" >>"$state/gh.log"
    case "$scenario" in
        list_fail)
            echo "boom" >&2
            exit 5
            ;;
        no_run)
            echo '[]'
            ;;
        appear)
            if [ "$(bump list)" -lt 2 ]; then
                echo '[]'
            else
                echo "[$(run_json 902 in_progress "" aaaa111122223333 2026-01-01T00:00:00Z)]"
            fi
            ;;
        stale_then_new)
            if [ "$(bump list)" -lt 2 ]; then
                echo "[$(run_json 901 completed success 0ldsha0000000000 2020-01-01T00:00:00Z)]"
            else
                echo "[$(run_json 902 in_progress "" aaaa111122223333 2026-01-01T00:00:00Z)]"
            fi
            ;;
        tip_bound)
            if [ "$(bump list)" -lt 2 ]; then
                echo "[$(run_json 900 in_progress "" 0ldsha0000000000 2020-01-01T00:00:00Z)]"
            else
                echo "[$(run_json 902 in_progress "" aaaa111122223333 2020-01-01T00:00:00Z)]"
            fi
            ;;
        commit)
            echo "[$(run_json 902 completed success aaaa111122223333 2020-01-01T00:00:00Z),$(run_json 901 completed success bbbb444455556666 2020-01-01T00:00:00Z)]"
            ;;
        rerun)
            if [ "$(bump list)" -lt 3 ]; then
                echo "[$(run_json 901 completed success aaaa111122223333 2020-01-01T00:00:00Z)]"
            else
                echo "[$(run_json 901 completed success aaaa111122223333 2020-01-01T00:00:00Z),$(run_json 902 in_progress "" aaaa111122223333 "$(now_iso)")]"
            fi
            ;;
        pending_prior)
            if [ "$(bump list)" -lt 3 ]; then
                echo "[$(run_json 900 in_progress "" aaaa111122223333 2020-01-01T00:00:00Z)]"
            else
                echo "[$(run_json 900 in_progress "" aaaa111122223333 2020-01-01T00:00:00Z),$(run_json 902 in_progress "" aaaa111122223333 "$(now_iso)")]"
            fi
            ;;
        commit_none)
            echo "[$(run_json 902 completed success aaaa111122223333 2020-01-01T00:00:00Z),$(run_json 901 completed success cccc777788889999 2020-01-01T00:00:00Z)]"
            ;;
        *)
            echo "[$STALE]"
            ;;
    esac
    exit 0
fi

echo "unexpected gh call: $*" >&2
exit 1
STUB
    chmod +x "$STUBS/gh"
    export PATH="$STUBS:$PATH"
    export DEPLOY_WAIT_STATE="$BATS_TEST_TMPDIR"
}

@test "mcp-meta describes the tool" {
    run bash "$TOOL" mcp-meta
    assert_success
    assert_output --partial '"name":"deploy-wait"'
    assert_output --partial '"timeoutMs":3600000'
    assert_output --partial "Exit codes carry the outcome"
}

@test "a successful run exits 0 and prints the digest" {
    export DEPLOY_WAIT_SCENARIO=success
    run bash "$TOOL" 901 --timeout 5 --interval 1
    assert_success
    assert_output --partial "Deploy run #901"
    assert_output --partial "success"
    assert_output --partial "aaaa1111"
}

@test "a failed run exits 3 and names the failing job" {
    export DEPLOY_WAIT_SCENARIO=failure
    run bash "$TOOL" 901 --timeout 5 --interval 1
    assert_equal "$status" 3
    assert_output --partial "Failing jobs"
    assert_output --partial "deploy"
}

@test "a cancelled run exits 3" {
    export DEPLOY_WAIT_SCENARIO=cancelled
    run bash "$TOOL" 901 --timeout 5 --interval 1
    assert_equal "$status" 3
    assert_output --partial "cancelled"
}

@test "a run still in progress is polled until it finishes" {
    export DEPLOY_WAIT_SCENARIO=finish
    run bash "$TOOL" 901 --timeout 10 --interval 1
    assert_success
    assert_output --partial "Deploy run #901"
}

@test "a run that never finishes exits 4" {
    export DEPLOY_WAIT_SCENARIO=in_progress
    run bash "$TOOL" 901 --timeout 1 --interval 1
    assert_equal "$status" 4
    refute_output --partial "ERROR:"
}

@test "a gh call cut off by the deadline is a timeout, not an error" {
    export DEPLOY_WAIT_SCENARIO=slow
    run bash "$TOOL" 901 --timeout 1 --interval 1
    assert_equal "$status" 4
    refute_output --partial "ERROR:"
}

@test "a gh failure exits 1 instead of polling to the timeout" {
    export DEPLOY_WAIT_SCENARIO=broken
    run bash "$TOOL" 901 --timeout 5 --interval 1
    assert_equal "$status" 1
    assert_output --partial "ERROR:"
}

@test "a workflow run that has not appeared yet is waited for" {
    export DEPLOY_WAIT_SCENARIO=appear
    run bash "$TOOL" --workflow deploy-staging.yml --branch main --timeout 10 --interval 1
    assert_success
    assert_output --partial "Deploy run #902"
}

@test "a run for another commit is not taken as this deployment" {
    export DEPLOY_WAIT_SCENARIO=stale_then_new
    run bash "$TOOL" --workflow deploy-staging.yml --branch main --timeout 10 --interval 1
    assert_success
    assert_output --partial "Deploy run #902"
    refute_output --partial "Deploy run #901"
}

@test "a run that never appears exits 4" {
    export DEPLOY_WAIT_SCENARIO=no_run
    run bash "$TOOL" --workflow deploy-staging.yml --branch main --timeout 1 --interval 1
    assert_equal "$status" 4
    assert_output --partial "no run"
}

@test "a failing run list is a runtime error, not a timeout" {
    export DEPLOY_WAIT_SCENARIO=list_fail
    run bash "$TOOL" --workflow deploy-staging.yml --branch main --timeout 5 --interval 1
    assert_equal "$status" 1
    assert_output --partial "ERROR:"
}

@test "--workflow without --branch or --commit is a usage error" {
    run bash "$TOOL" --workflow deploy-staging.yml --timeout 5 --interval 1
    assert_equal "$status" 2
    assert_output --partial "needs --branch or --commit"
}

@test "--commit selects the run for that commit, not the newest" {
    export DEPLOY_WAIT_SCENARIO=commit
    run bash "$TOOL" --workflow deploy-staging.yml --commit bbbb4444 --last --timeout 5 --interval 1
    assert_success
    assert_output --partial "Deploy run #901"
    assert_output --partial "bbbb4444"
    # The filter must go to gh, not wait until the newest 50 runs are fetched.
    grep -q -- '--commit bbbb444455556666' "$BATS_TEST_TMPDIR/gh.log"
}

@test "a completed run from before the call times out and points at --last" {
    export DEPLOY_WAIT_SCENARIO=commit
    run bash "$TOOL" --workflow deploy-staging.yml --commit bbbb4444 --timeout 1 --interval 1
    assert_equal "$status" 4
    assert_output --partial "pass --last"
}

@test "a repeated deployment waits for the new run, not the previous one" {
    export DEPLOY_WAIT_SCENARIO=rerun
    run bash "$TOOL" --workflow deploy-staging.yml --branch main --timeout 10 --interval 1
    assert_success
    assert_output --partial "Deploy run #902"
    refute_output --partial "Deploy run #901"
}

@test "an in-progress run from before the call is not taken for a rerun" {
    export DEPLOY_WAIT_SCENARIO=pending_prior
    run bash "$TOOL" --workflow deploy-staging.yml --branch main --timeout 10 --interval 1
    assert_success
    assert_output --partial "Deploy run #902"
    refute_output --partial "Deploy run #900"
}

@test "--commit with no matching run times out instead of taking another" {
    export DEPLOY_WAIT_SCENARIO=commit_none
    run bash "$TOOL" --workflow deploy-staging.yml --commit deadbeef --timeout 1 --interval 1
    assert_equal "$status" 4
}

@test "--branch binds the run to the branch tip, not an older in-progress one" {
    export DEPLOY_WAIT_SCENARIO=tip_bound
    run bash "$TOOL" --workflow deploy-staging.yml --branch main --timeout 10 --interval 1
    assert_success
    assert_output --partial "Deploy run #902"
    refute_output --partial "Deploy run #900"
    # The tip also goes upstream, so a busy branch cannot page the run away.
    grep -q -- '--commit aaaa111122223333' "$BATS_TEST_TMPDIR/gh.log"
}

@test "a branch tip that cannot be resolved is a runtime error" {
    export DEPLOY_WAIT_SCENARIO=tip_bound
    export DEPLOY_WAIT_TIP_FAIL=1
    run bash "$TOOL" --workflow deploy-staging.yml --branch main --timeout 5 --interval 1
    assert_equal "$status" 1
    assert_output --partial "ERROR:"
}

@test "no arguments is a usage error" {
    run bash "$TOOL"
    assert_equal "$status" 2
    assert_output --partial "ERROR:"
}

@test "an argument that is not a run is a usage error" {
    run bash "$TOOL" not-a-run
    assert_equal "$status" 2
    assert_output --partial "not a deploy run"
}

@test "a run id and --workflow together is a usage error" {
    run bash "$TOOL" 901 --workflow deploy-staging.yml
    assert_equal "$status" 2
    assert_output --partial "not both"
}

@test "--commit with a run id is a usage error, not silently ignored" {
    run bash "$TOOL" 901 --commit bbbb4444
    assert_equal "$status" 2
    assert_output --partial "apply to --workflow"
}

@test "json output carries the outcome" {
    export DEPLOY_WAIT_SCENARIO=success
    run bash "$TOOL" 901 --timeout 5 --interval 1 --json
    assert_success
    assert_output --partial '"status": "success"'
    assert_output --partial '"repository": "GET-E/dev-bot"'
    assert_output --partial '"id": 901'
}

@test "json output carries a failed outcome" {
    export DEPLOY_WAIT_SCENARIO=failure
    run bash "$TOOL" 901 --timeout 5 --interval 1 --json
    assert_equal "$status" 3
    assert_output --partial '"status": "failed"'
    assert_output --partial '"conclusion": "failure"'
    assert_output --partial '"name": "deploy"'
}

@test "json output carries a timeout outcome" {
    export DEPLOY_WAIT_SCENARIO=no_run
    run bash "$TOOL" --workflow deploy-staging.yml --branch main --timeout 1 --interval 1 --json
    assert_equal "$status" 4
    assert_output --partial '"status": "timeout"'
}

@test "a run URL and owner/repo#id use the slug, not the local repo" {
    export DEPLOY_WAIT_SCENARIO=success
    export DEPLOY_WAIT_NO_REPO_VIEW=1

    run bash "$TOOL" "https://github.com/other/repo/actions/runs/901" --timeout 5 --interval 1
    assert_success
    assert_output --partial "other/repo"

    run bash "$TOOL" "other/repo#901" --timeout 5 --interval 1
    assert_success
    assert_output --partial "other/repo"
}

@test "a run URL with a query or fragment is accepted" {
    export DEPLOY_WAIT_SCENARIO=success
    run bash "$TOOL" "https://github.com/GET-E/dev-bot/actions/runs/901?check_suite_focus=true" --timeout 5 --interval 1
    assert_success
    assert_output --partial "Deploy run #901"

    run bash "$TOOL" "https://github.com/GET-E/dev-bot/actions/runs/901#logs" --timeout 5 --interval 1
    assert_success
}

@test "a run URL, a #number and an owner/repo#number are all accepted" {
    export DEPLOY_WAIT_SCENARIO=success
    run bash "$TOOL" "https://github.com/GET-E/dev-bot/actions/runs/901" --timeout 5 --interval 1
    assert_success
    assert_output --partial "Deploy run #901"

    run bash "$TOOL" "#901" --timeout 5 --interval 1
    assert_success

    run bash "$TOOL" "GET-E/dev-bot#901" --timeout 5 --interval 1
    assert_success
}
