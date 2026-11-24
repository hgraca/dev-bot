#!/usr/bin/env bash
# ---
# description: Security tooling façade — one interface over four delivery backends, so a skill names a tool and never learns whether it is a local binary, a uvx invocation, a container or a system package
# ---
# =============================================================================
# src/agentic/security/scripts/tooling.sh
#
# One façade, four backends. The backend is an implementation detail of this
# file: run <tool> and it dispatches. `check` prints what is present, which is
# also the coverage ledger a report cites for a check it could not run.
#
#   check                — tool → backend → status → the checks it enables
#   run <tool> [args…]   — dispatch to the backend that serves <tool>
#   install [tool…]      — provision what can be provisioned, skip the rest
#   --help
#
# Backends:
#   go      Go module installed into <store>/bin, version recorded after the
#           fact — NOT pinned; see the note in `install`
#   uvx     resolved per invocation to the current release
#   docker  image pulled at install, run with --rm per call
#   system  the distro owns it; we only report presence
#
# Nothing here is intrusive. Every tool it can install is read-only or advisory
# by default; the intrusive ones are named in the manifest so a report can say
# which checks it therefore did not run.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
STORE_DIR="${SEC_TOOLS_DIR:-${REPO_ROOT}/storage/security-tools}"
BIN_DIR="${STORE_DIR}/bin"
VERSIONS_FILE="${STORE_DIR}/versions.txt"

# name|backend|source|checks-enabled
# The source column is the Go module path, the PyPI name, or the image reference.
MANIFEST=$(cat <<'EOF'
semgrep|uvx|semgrep|A05 A07 static source patterns
bandit|uvx|bandit|python source patterns
sqlmap|uvx|sqlmap|A05 injection confirmation, intrusive
nuclei|go|github.com/projectdiscovery/nuclei/v3/cmd/nuclei|scanner hypotheses
ffuf|go|github.com/ffuf/ffuf/v2|entry-point discovery
gitleaks|go|github.com/gitleaks/gitleaks/v8|A04 secrets in source and history
zap|docker|zaproxy/zap-stable|A01 A02 A05 runtime headers CORS redirect
trivy|docker|aquasec/trivy|A03 dependency and image CVEs
metasploit|docker|metasploitframework/metasploit-framework|exploit validation, intrusive
nmap|system|nmap|A02 ports and service fingerprint
tcpdump|system|tcpdump|evidence of what crossed the wire
hydra|system|hydra|A07 brute force, lockout-aware
nikto|system|nikto|web server scan, hypotheses only
EOF
)

usage() {
    cat <<'EOF'
Security tooling façade.

  tooling.sh check                 Report every tool: backend, status, checks it enables
  tooling.sh run <tool> [args...]  Run a tool through whichever backend serves it
  tooling.sh install [tool...]     Provision what can be provisioned; skip the rest
  tooling.sh --help

Environment:
  SEC_TOOLS_DIR             where Go binaries and the version record live
                            (default: <repo>/storage/security-tools)
  SEC_TOOLS_DOCKER_NETWORK  network mode for container tools (default: none —
                            pass bridge or host when the run must reach the target)
  SEC_TOOLS_DOCKER_OUT      host directory mounted writable at /out, so a
                            container tool can write its report
  SEC_TOOLS_DOCKER_ARGS     extra flags for `docker run`, word-split
  SEC_TOOLS_FORCE           re-fetch what is already present on `install`

Container runs mount the caller's working directory read-only at /src and run
there, so a filesystem scan inspects the project rather than the container.

Exit codes: 0 success, 3 tool unavailable, 2 usage error. Any other non-zero
status is the tool's own — `run` execs it, so its exit status is returned.
EOF
}

manifest_line() {
    local tool="$1"
    printf '%s\n' "${MANIFEST}" | awk -F'|' -v t="${tool}" '$1 == t'
}

tool_names() {
    printf '%s\n' "${MANIFEST}" | cut -d'|' -f1
}

recorded_version() {
    [ -f "${VERSIONS_FILE}" ] || return 0
    # Last match wins: a forced refresh appends, so the first row is the oldest.
    awk -v t="$1" '$1 == t { v = $2 } END { if (v != "") print v }' "${VERSIONS_FILE}"
}

system_present() {
    command -v "$1" >/dev/null 2>&1
}

go_present() {
    [ -x "${BIN_DIR}/$1" ]
}

uvx_present() {
    command -v uvx >/dev/null 2>&1
}

docker_present() {
    command -v docker >/dev/null 2>&1 &&
        docker image inspect "$1" >/dev/null 2>&1
}

# Prints "present" or "absent" for one tool, given its manifest line.
status_of() {
    local backend="$2" source="$3"
    case "${backend}" in
        go) go_present "$1" && echo present || echo absent ;;
        uvx) uvx_present && echo resolve || echo absent ;;
        docker) docker_present "${source}" && echo present || echo absent ;;
        system) system_present "${source}" && echo present || echo absent ;;
        *) echo absent ;;
    esac
}

cmd_check() {
    printf '%-11s %-7s %-8s %s\n' TOOL BACKEND STATUS ENABLES
    local name backend source checks status version
    while IFS='|' read -r name backend source checks; do
        [ -n "${name}" ] || continue
        status="$(status_of "${name}" "${backend}" "${source}")"
        version="$(recorded_version "${name}")"
        [ -n "${version}" ] && status="${status} ${version}"
        printf '%-11s %-7s %-8s %s\n' "${name}" "${backend}" "${status}" "${checks}"
    done <<<"${MANIFEST}"
    printf '\nA check needing an absent tool is reported as skipped, never as passed.\n'
    if uvx_present; then
        printf 'resolve: uvx is present; the tool is fetched on first use, not cached here.\n'
    else
        printf 'absent: uvx is not installed, so every uvx-backed row above is absent.\n'
    fi
}

cmd_run() {
    local tool="${1:-}"
    shift || true
    if [ -z "${tool}" ]; then
        printf 'ERROR: run needs a tool name. Try: tooling.sh check\n' >&2
        return 2
    fi

    local line backend source
    line="$(manifest_line "${tool}")"
    if [ -z "${line}" ]; then
        printf 'ERROR: unknown tool %s. Try: tooling.sh check\n' "${tool}" >&2
        return 2
    fi
    IFS='|' read -r _ backend source _ <<<"${line}"

    case "${backend}" in
        go)
            if ! go_present "${tool}"; then
                printf 'WARN: %s is not installed: tooling.sh install %s\n' "${tool}" "${tool}" >&2
                return 3
            fi
            exec "${BIN_DIR}/${tool}" "$@"
            ;;
        uvx)
            if ! uvx_present; then
                printf 'WARN: uvx is not available, cannot serve %s\n' "${tool}" >&2
                return 3
            fi
            # No `--` separator: uvx passes everything after the command
            # straight through, and a `--` here becomes the tool's first arg.
            exec uvx "${source}" "$@"
            ;;
        docker)
            if ! command -v docker >/dev/null 2>&1; then
                printf 'WARN: docker is not available, cannot serve %s\n' "${tool}" >&2
                return 3
            fi
            # `docker run` pulls implicitly when the image is absent, which would
            # turn a local run into a network fetch that `check` called absent.
            if ! docker image inspect "${source}" >/dev/null 2>&1; then
                printf 'WARN: %s is not pulled: tooling.sh install %s\n' "${tool}" "${tool}" >&2
                return 3
            fi
            # An array: `--network none` must reach docker as two arguments, not
            # as the single literal "--network none".
            local -a net_args=(--network none)
            if [ -n "${SEC_TOOLS_DOCKER_NETWORK:-}" ]; then
                net_args=(--network "${SEC_TOOLS_DOCKER_NETWORK}")
            fi
            # Mount the caller's tree: without it a filesystem scan inspects the
            # container and returns a confident, irrelevant result.
            local -a mount_args=(-v "${PWD}:/src:ro" -w /src)
            if [ -n "${SEC_TOOLS_DOCKER_OUT:-}" ]; then
                mount_args+=(-v "${SEC_TOOLS_DOCKER_OUT}:/out")
            fi
            # shellcheck disable=SC2086
            exec docker run --rm -i "${net_args[@]}" "${mount_args[@]}" \
                ${SEC_TOOLS_DOCKER_ARGS:-} "${source}" "$@"
            ;;
        system)
            if ! system_present "${source}"; then
                printf 'WARN: %s is not installed; install it with your package manager\n' "${tool}" >&2
                return 3
            fi
            exec "${source}" "$@"
            ;;
        *)
            printf 'ERROR: unknown backend %s for %s\n' "${backend}" "${tool}" >&2
            return 2
            ;;
    esac
}

install_one() {
    local tool="$1" line backend source version
    line="$(manifest_line "${tool}")"
    if [ -z "${line}" ]; then
        printf 'ERROR: unknown tool %s\n' "${tool}" >&2
        return 2
    fi
    IFS='|' read -r _ backend source _ <<<"${line}"

    case "${backend}" in
        go)
            if go_present "${tool}" && [ -z "${SEC_TOOLS_FORCE:-}" ]; then
                printf '  ok    %-10s already installed\n' "${tool}"
                return 0
            fi
            if ! command -v go >/dev/null 2>&1; then
                printf '  warn  %-10s no go toolchain\n' "${tool}"
                return 1
            fi
            printf '  get   %-10s %s\n' "${tool}" "${source}"
            mkdir -p "${BIN_DIR}"
            if ! GOBIN="${BIN_DIR}" go install "${source}@latest" >/dev/null 2>&1; then
                printf '  warn  %-10s go install failed; check network\n' "${tool}"
                return 1
            fi
            version="$("${BIN_DIR}/${tool}" -version 2>/dev/null | head -1 || true)"
            if [ -n "${version}" ]; then
                printf '%s %s\n' "${tool}" "${version}" >>"${VERSIONS_FILE}"
            fi
            ;;
        uvx)
            if ! uvx_present; then
                printf '  warn  %-10s uvx is not installed\n' "${tool}"
                return 1
            fi
            printf '  ok    %-10s resolved per call by uvx\n' "${tool}"
            ;;
        docker)
            if ! command -v docker >/dev/null 2>&1; then
                printf '  skip  %-10s no docker\n' "${tool}"
                return 0
            fi
            if docker image inspect "${source}" >/dev/null 2>&1 && [ -z "${SEC_TOOLS_FORCE:-}" ]; then
                printf '  ok    %-10s already pulled\n' "${tool}"
                return 0
            fi
            printf '  pull  %-10s %s\n' "${tool}" "${source}"
            if ! docker pull --quiet "${source}" >/dev/null 2>&1; then
                printf '  warn  %-10s pull failed; check network\n' "${tool}"
                return 1
            fi
            ;;
        system)
            printf '  skip  %-10s distro-owned; install with your package manager\n' "${tool}"
            ;;
    esac
    return 0
}

cmd_install() {
    # Unpinned by design: versions resolve at install time and are recorded in
    # versions.txt, so a refresh is reproducible from that record but a first
    # install is not. Pinning means maintaining a version table here; until it
    # exists, the module's own A03 checklist applies to this file too.
    mkdir -p "${STORE_DIR}"
    local failed=0
    if [ "$#" -eq 0 ]; then
        while IFS= read -r name; do
            install_one "${name}" || failed=$((failed + 1))
        done < <(tool_names)
    else
        local name
        for name in "$@"; do
            install_one "${name}" || failed=$((failed + 1))
        done
    fi
    printf '\nstore: %s\n\n' "${STORE_DIR}"
    # End with the ledger: a partial install is only useful if the caller can
    # see which tools it did not get.
    cmd_check
    if [ "${failed}" -gt 0 ]; then
        printf '\nWARN: %s tool(s) failed to provision\n' "${failed}" >&2
        return 1
    fi
}

main() {
    local cmd="${1:-}"
    [ "$#" -gt 0 ] && shift
    case "${cmd}" in
        check) cmd_check ;;
        run) cmd_run "$@" ;;
        install) cmd_install "$@" ;;
        --help | -h | "") usage ;;
        *)
            printf 'ERROR: unknown command %s\n' "${cmd}" >&2
            usage >&2
            return 2
            ;;
    esac
}

main "$@"
