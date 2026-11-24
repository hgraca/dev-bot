#!/usr/bin/env bats
# =============================================================================
# src/agentic/security/tests/tooling_tests.bats
# Contract for the tooling façade: four backends behind one interface, a check
# that doubles as the coverage ledger, and an install that never touches what
# the distro owns.
# =============================================================================

setup() {
    bats_load_library bats-support
    bats_load_library bats-assert

    MODULE="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    TOOLING="${MODULE}/scripts/tooling.sh"
    export SEC_TOOLS_DIR="${BATS_TEST_TMPDIR}/store"
    STUB_BIN="${BATS_TEST_TMPDIR}/stub"
    mkdir -p "${STUB_BIN}"
    export PATH="${STUB_BIN}:${PATH}"
}

stub_system_tool() {
    printf '#!/usr/bin/env bash\necho "stub-%s $*"\n' "$1" >"${STUB_BIN}/$1"
    chmod +x "${STUB_BIN}/$1"
}

stub_store_tool() {
    mkdir -p "${SEC_TOOLS_DIR}/bin"
    printf '#!/usr/bin/env bash\necho "stub-%s $*"\n' "$1" >"${SEC_TOOLS_DIR}/bin/$1"
    chmod +x "${SEC_TOOLS_DIR}/bin/$1"
}

@test "the script parses" {
    run bash -n "${TOOLING}"
    assert_success
}

@test "help documents the three verbs" {
    run bash "${TOOLING}" --help
    assert_success
    assert_output --partial 'tooling.sh check'
    assert_output --partial 'tooling.sh run'
    assert_output --partial 'tooling.sh install'
}

@test "check reports every backend and every manifest tool" {
    run bash "${TOOLING}" check
    assert_success
    local backend
    for backend in go uvx docker system; do
        assert_output --partial "${backend}"
    done
    local tool
    for tool in semgrep nuclei zap nmap gitleaks; do
        assert_output --partial "${tool}"
    done
}

@test "check states that an absent tool means a skipped check" {
    # The ledger half of the contract: absence is recorded, never passed.
    run bash "${TOOLING}" check
    assert_success
    assert_output --partial 'reported as skipped, never as passed'
}

@test "run dispatches a system tool found on PATH" {
    stub_system_tool nmap
    run bash "${TOOLING}" run nmap -p 443 example.invalid
    assert_success
    assert_output 'stub-nmap -p 443 example.invalid'
}

@test "run dispatches a go tool installed in the store" {
    stub_store_tool nuclei
    run bash "${TOOLING}" run nuclei -u https://example.invalid
    assert_success
    assert_output 'stub-nuclei -u https://example.invalid'
}

@test "run dispatches a uvx tool without injecting a separator" {
    stub_system_tool uvx
    run bash "${TOOLING}" run semgrep --config p/php .
    assert_success
    # uvx must receive the command first and the tool's argv unchanged: a `--`
    # after the command is handed to the tool and ends its option parsing.
    assert_output 'stub-uvx semgrep --config p/php .'
}

@test "run dispatches a container tool with --rm and no network by default" {
    stub_system_tool docker
    run bash "${TOOLING}" run trivy image alpine
    assert_success
    # No egress unless the caller opts in: a scanner that must reach the target
    # sets SEC_TOOLS_DOCKER_NETWORK.
    assert_output 'stub-docker run --rm -i --network none aquasec/trivy image alpine'
}

@test "container networking is opt-in" {
    stub_system_tool docker
    SEC_TOOLS_DOCKER_NETWORK=bridge run bash "${TOOLING}" run trivy image alpine
    assert_success
    assert_output --partial '--network bridge'
}

@test "check pairs each tool with the backend that serves it" {
    run bash "${TOOLING}" check
    assert_success
    local pair name want got
    for pair in 'semgrep:uvx' 'nuclei:go' 'zap:docker' 'nmap:system'; do
        name="${pair%%:*}"
        want="${pair##*:}"
        got="$(printf '%s\n' "$output" | awk -v n="${name}" '$1 == n { print $2 }')"
        [ "${got}" = "${want}" ] || fail "${name}: expected backend ${want}, got '${got}'"
    done
}

@test "run refuses an unknown tool with a usage error" {
    run bash "${TOOLING}" run nosuchtool
    assert_failure 2
    assert_output --partial 'unknown tool nosuchtool'
}

@test "an unknown command is a usage error, not a silent no-op" {
    run bash "${TOOLING}" frobnicate
    assert_failure 2
    assert_output --partial 'unknown command frobnicate'
}

@test "run warns rather than silently doing nothing for an absent tool" {
    command -v nikto >/dev/null 2>&1 && skip 'nikto installed on this host'
    run bash "${TOOLING}" run nikto -h https://example.invalid
    # 3 is reserved for "absent", so it cannot be confused with a tool that ran
    # and failed — which returns its own status through exec.
    assert_failure 3
    assert_output --partial 'WARN: nikto is not installed'
}

@test "install never provisions a distro-owned tool" {
    run bash "${TOOLING}" install nmap
    assert_success
    assert_output --partial 'distro-owned'
}

@test "install is idempotent for a tool already in the store" {
    stub_store_tool ffuf
    run bash "${TOOLING}" install ffuf
    assert_success
    assert_output --partial 'already installed'
}

@test "a uvx-backed tool reads as resolvable, not installed" {
    # `uvx` present does not mean the tool is cached; saying "present" would
    # claim more than was checked, which is the dishonesty this ledger exists
    # to remove elsewhere.
    command -v uvx >/dev/null 2>&1 || skip 'uvx not installed on this host'
    run bash "${TOOLING}" check
    assert_success
    assert_output --partial 'resolve'
}

@test "an empty store reports a go tool absent rather than ready" {
    # The ledger must survive a fresh machine: a tool nobody installed is absent.
    run bash "${TOOLING}" check
    assert_success
    local row
    row="$(printf '%s\n' "$output" | awk '$1 == "nuclei" { print $3 }')"
    [ "${row}" = 'absent' ] || fail "expected nuclei absent, got '${row}'"
}

@test "every manifest line names a backend the dispatcher knows" {
    # A typo in the manifest is otherwise only visible when that tool is used.
    # Scope the scan to the MANIFEST heredoc: the rest of the file is full of pipes.
    local bad
    bad="$(awk '
        /^MANIFEST=/ && /<<.EOF./ { inside = 1; next }
        inside && /^EOF$/ { inside = 0; next }
        inside && /\|/ {
            split($0, f, "|")
            if (f[2] !~ /^(go|uvx|docker|system)$/) print f[2]
        }
    ' "${TOOLING}")"
    [ -z "${bad}" ] || fail "unknown backend in manifest: ${bad}"
}
