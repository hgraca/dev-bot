#!/usr/bin/env bats
# =============================================================================
# src/agentic/security/tests/probe_tests.bats
# Contract for the external-pentest probe script: each check's verdict logic,
# the exit-code aggregation, the read-only guarantee, and the CLI contract.
# No test touches the network — the check functions take already-fetched text,
# and the end-to-end tests put a stub curl on PATH.
# =============================================================================

setup() {
    bats_load_library bats-support
    bats_load_library bats-assert

    MODULE="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    PROBE="${MODULE}/skills/pentest-external-webapp/scripts/probe.sh"

    source "$PROBE"
}

# stub_curl <dir> <body> — a curl that prints <body> and succeeds.
stub_curl() {
    mkdir -p "$1"
    {
        printf '#!/usr/bin/env bash\n'
        printf 'printf %%s %q\n' "$2"
        printf 'exit 0\n'
    } >"$1/curl"
    chmod +x "$1/curl"
}

# stub_curl_router <dir> <sentinel-status> <other-status> — answers the sentinel
# path differently, so a site that serves files but 404s unknown paths is modelled.
stub_curl_router() {
    mkdir -p "$1"
    {
        printf '#!/usr/bin/env bash\n'
        printf 'case "$*" in\n'
        printf '  *__probe_missing*) printf %%s %q ;;\n' "$2"
        printf '  *) printf %%s %q ;;\n' "$3"
        printf 'esac\nexit 0\n'
    } >"$1/curl"
    chmod +x "$1/curl"
}

# --- HSTS -------------------------------------------------------------------

@test "check_hsts passes a one-year max-age" {
    run check_hsts "strict-transport-security: max-age=31536000; includeSubDomains" example.com
    assert_output --partial "PASS"
    refute_output --partial "FAIL"
}

@test "check_hsts fails when the header is absent" {
    run check_hsts "content-type: text/html" example.com
    assert_output --partial "FAIL"
    assert_output --partial "HSTS missing"
}

@test "check_hsts fails a max-age below one year" {
    run check_hsts "strict-transport-security: max-age=600" example.com
    assert_output --partial "FAIL"
    assert_output --partial "below one year"
}

@test "check_hsts fails a header with no max-age" {
    run check_hsts "strict-transport-security: includeSubDomains" example.com
    assert_output --partial "FAIL"
    assert_output --partial "no max-age"
}

# --- HTTPS enforcement ------------------------------------------------------

@test "check_https_enforcement passes a redirect to HTTPS" {
    run check_https_enforcement 301 "https://example.com/" example.com "https://example.com:443"
    assert_output --partial "PASS"
    refute_output --partial "FAIL"
}

@test "check_https_enforcement fails a redirect to a different host" {
    # A host-changing redirect is not enforcement of this target's HTTPS.
    run check_https_enforcement 301 "https://attacker.invalid/" example.com "https://example.com:443"
    assert_output --partial "FAIL"
    assert_output --partial "not to"
}

@test "check_https_enforcement fails a redirect that does not reach HTTPS" {
    run check_https_enforcement 302 "http://example.com/" example.com
    assert_output --partial "FAIL"
    assert_output --partial "not HTTPS"
}

@test "check_https_enforcement fails a redirect with no target" {
    run check_https_enforcement 301 "" example.com
    assert_output --partial "FAIL"
    assert_output --partial "no target"
}

@test "check_https_enforcement fails content served on port 80" {
    run check_https_enforcement 200 "" example.com
    assert_output --partial "FAIL"
    assert_output --partial "no HTTPS enforcement"
}

@test "check_https_enforcement reports silence as unknown" {
    run check_https_enforcement 000 "" example.com
    assert_output --partial "UNKNOWN"
}

# --- CORS -------------------------------------------------------------------

@test "check_cors fails a reflected origin with credentials" {
    run check_cors "access-control-allow-origin: https://attacker.invalid
access-control-allow-credentials: true" example.com/api
    assert_output --partial "FAIL"
    assert_output --partial "reflects https://attacker.invalid"
}

@test "check_cors fails a wildcard with credentials" {
    run check_cors "access-control-allow-origin: *
access-control-allow-credentials: true" example.com/api
    assert_output --partial "FAIL"
    assert_output --partial "invalid and unsafe"
}

@test "check_cors passes a wildcard without credentials" {
    run check_cors "access-control-allow-origin: *" example.com/api
    assert_output --partial "PASS"
    refute_output --partial "FAIL"
}

@test "check_cors passes a fixed allowlist origin" {
    run check_cors "access-control-allow-origin: https://app.example.com" example.com/api
    assert_output --partial "PASS"
    refute_output --partial "FAIL"
}

@test "check_cors trims optional whitespace before judging a wildcard" {
    # "* " with a trailing space must not read as a fixed allowlist.
    run check_cors "access-control-allow-origin: * 
access-control-allow-credentials: true " example.com/api
    assert_output --partial "FAIL"
    assert_output --partial "invalid and unsafe"
}

@test "check_cors does not mistake a lookalike origin for reflection" {
    # https://notattacker.invalid is not https://attacker.invalid.
    run check_cors "access-control-allow-origin: https://notattacker.invalid
access-control-allow-credentials: true" example.com/api
    assert_output --partial "PASS"
    refute_output --partial "FAIL"
}

@test "check_cors fails an exact origin reflection with credentials" {
    run check_cors "access-control-allow-origin: https://attacker.invalid
access-control-allow-credentials: true" example.com/api
    assert_output --partial "FAIL"
}

@test "check_cors passes when the header is absent" {
    run check_cors "content-type: application/json" example.com/api
    assert_output --partial "PASS"
    assert_output --partial "no CORS allow-origin header"
}

@test "the cors command judges HEAD, GET and OPTIONS, not HEAD alone" {
    # Bare assertion on purpose: assert_* routes through fail(), which is the
    # very function this file has to prove cannot be shadowed.
    grep -qE 'for method in HEAD GET OPTIONS' "$PROBE"
}

# --- redirect ---------------------------------------------------------------

@test "check_redirect fails a destination on another host" {
    run check_redirect "https://book.example.com/en/completed" "https://attacker.invalid/"
    assert_output --partial "FAIL"
    assert_output --partial "leaves"
}

@test "check_redirect fails a destination on the same host but another port" {
    run check_redirect "https://book.example.com/en/completed" "https://book.example.com:6666/x"
    assert_output --partial "FAIL"
}

@test "check_redirect passes a destination on the same origin" {
    run check_redirect "https://book.example.com/en/completed" "https://book.example.com/en/home"
    assert_output --partial "PASS"
    refute_output --partial "FAIL"
}

@test "check_redirect passes when no redirect is issued" {
    run check_redirect "https://book.example.com/en/completed" ""
    assert_output --partial "PASS"
    assert_output --partial "no redirect issued"
}

@test "the redirect command reports an endpoint that no longer exists as unknown" {
    stub_curl "$BATS_TEST_TMPDIR/gone" "404 "
    run env PATH="$BATS_TEST_TMPDIR/gone:$PATH" bash "$PROBE" redirect https://book.example.com/en/completed
    [ "$status" -eq 0 ]
    assert_output --partial "confirm it still exists"
    refute_output --partial "PASS     parameter ignored"
}

@test "the redirect command reports an ignored parameter as a pass" {
    stub_curl "$BATS_TEST_TMPDIR/ignored" "200 "
    run env PATH="$BATS_TEST_TMPDIR/ignored:$PATH" bash "$PROBE" redirect https://book.example.com/en/completed
    [ "$status" -eq 0 ]
    assert_output --partial "parameter ignored"
}

# --- files ------------------------------------------------------------------

@test "check_file_status fails a served configuration file" {
    run check_file_status "/web.config" 200 none
    assert_output --partial "FAIL"
    assert_output --partial "is served"
}

@test "check_file_status passes a forbidden file" {
    run check_file_status "/.env" 403 none
    assert_output --partial "PASS"
    refute_output --partial "FAIL"
}

@test "check_file_status does not fail a catch-all router with an identical body" {
    run check_file_status "/backup.zip" 200 identical
    assert_output --partial "UNKNOWN"
    assert_output --partial "catch-all"
    refute_output --partial "FAIL"
}

@test "check_file_status does not fail a site that answers 200 for unknown paths" {
    run check_file_status "/backup.zip" 200 ambiguous
    assert_output --partial "UNKNOWN"
    assert_output --partial "verify by hand"
    refute_output --partial "FAIL"
}

@test "check_file_status reports an unparsed response as unknown" {
    run check_file_status "/backup.zip" 500 none
    assert_output --partial "UNKNOWN"
}

@test "the files command reports a published security.txt as informational" {
    stub_curl "$BATS_TEST_TMPDIR/securitytxt" "200"
    run env PATH="$BATS_TEST_TMPDIR/securitytxt:$PATH" bash "$PROBE" files https://example.com
    assert_output --partial "INFO"
    assert_output --partial "security.txt is published"
    refute_output --partial "FAIL     /.well-known/security.txt"
}

@test "the files command exits 0 when nothing is served" {
    stub_curl "$BATS_TEST_TMPDIR/pass" "404"
    run env PATH="$BATS_TEST_TMPDIR/pass:$PATH" bash "$PROBE" files https://example.com
    [ "$status" -eq 0 ]
    assert_output --partial "0 failed"
    refute_output --partial "FAIL"
}

@test "the files command exits 1 when a file is served" {
    stub_curl_router "$BATS_TEST_TMPDIR/served" "404" "200"
    run env PATH="$BATS_TEST_TMPDIR/served:$PATH" bash "$PROBE" files https://example.com
    [ "$status" -eq 1 ]
    assert_output --partial "is served"
    assert_output --partial "failed"
}

@test "the files command does not fail a site that answers 200 for unknown paths" {
    stub_curl "$BATS_TEST_TMPDIR/catchall" "200"
    run env PATH="$BATS_TEST_TMPDIR/catchall:$PATH" bash "$PROBE" files https://example.com
    [ "$status" -eq 0 ]
    refute_output --partial "is served"
}

# --- ports ------------------------------------------------------------------

@test "check_port fails an unexpected open port" {
    run check_port 9090 0 1
    assert_output --partial "FAIL"
    assert_output --partial "accepted a TCP connection"
}

@test "check_port fails a port that accepts and then stays silent" {
    run check_port 9090 28 1
    assert_output --partial "FAIL"
}

@test "check_port reports a blackholed port as unknown, not open" {
    run check_port 9090 28 0
    assert_output --partial "UNKNOWN"
    refute_output --partial "FAIL"
}

@test "check_port reports an unresolvable host as unknown" {
    run check_port 9090 6 0
    assert_output --partial "UNKNOWN"
    assert_output --partial "could not be resolved"
}

@test "check_port passes an expected open port" {
    run check_port 443 0 1
    assert_output --partial "PASS"
    assert_output --partial "expected"
    refute_output --partial "FAIL"
}

@test "check_port passes a closed port" {
    run check_port 9090 7 0
    assert_output --partial "PASS"
    assert_output --partial "closed or filtered"
    refute_output --partial "FAIL"
}

@test "check_port fails an expected port that does not answer" {
    run check_port 443 7 0
    assert_output --partial "FAIL"
    assert_output --partial "expected to serve the application"
}

@test "a documented expected port can be declared through the environment" {
    stub_curl "$BATS_TEST_TMPDIR/connects" "1"
    run env PATH="$BATS_TEST_TMPDIR/connects:$PATH" PROBE_EXPECTED_PORTS="80 443 8443" \
        bash "$PROBE" ports example.com 8443
    [ "$status" -eq 0 ]
    assert_output --partial "port 8443 open (expected)"
    refute_output --partial "FAIL"
}

# --- read-only guarantee ----------------------------------------------------

@test "the probe script issues no state-changing request" {
    # Bare assertion: a negated grep fails the test by its own exit code.
    ! grep -qE -- '(-X[[:space:]]*(POST|PUT|PATCH|DELETE)|--data|--upload-file|-T[[:space:]]|-F[[:space:]]|--form)' "$PROBE"
}

@test "every curl call terminates its options before the target" {
    # A URL beginning with '-' must never be parsed as an option. Bare assertions:
    # fail() itself is what this file must not trust.
    local calls seps
    calls="$(grep -c 'curl -q -sS' "$PROBE")"
    seps="$(grep -c -- ' -- "' "$PROBE")"
    if [ "$calls" -le 0 ]; then
        echo "no curl call found to check" >&2
        return 1
    fi
    if [ "$seps" -lt "$calls" ]; then
        echo "only $seps of $calls curl calls use --" >&2
        return 1
    fi
}

@test "every curl call disables ambient configuration" {
    # ~/.curlrc could set request=POST or data=..., turning a read-only probe into
    # a state-changing one. -q must be curl's first argument to take effect.
    local calls guarded
    calls="$(grep -c 'curl -' "$PROBE")"
    guarded="$(grep -c 'curl -q -' "$PROBE")"
    if [ "$calls" -le 0 ]; then
        echo "no curl call found to check" >&2
        return 1
    fi
    if [ "$guarded" -lt "$calls" ]; then
        echo "only $guarded of $calls curl calls disable the config" >&2
        return 1
    fi
}

@test "the probe script does not shadow shell or harness builtins" {
    # Sourcing the script must not replace bats-support's fail(). This guard must
    # itself be a bare assertion, or a reintroduced fail() disables it too.
    # Any declaration form counts: `fail()`, `fail ()`, `function fail ()`.
    ! grep -qE '^[[:space:]]*(function[[:space:]]+)?(pass|fail|unknown|info)[[:space:]]*\(\)' "$PROBE"
}

# --- CLI --------------------------------------------------------------------

@test "the headers command reads HSTS from the secure origin even when given http" {
    # HSTS received over plain HTTP is ignored by browsers, so it must be read
    # from https. The stub answers HSTS only on the https URL.
    mkdir -p "$BATS_TEST_TMPDIR/httpin"
    cat >"$BATS_TEST_TMPDIR/httpin/curl" <<'STUB'
#!/usr/bin/env bash
case "$*" in
    *"-w"*) printf '301 https://example.com/' ;;
    *https://example.com*) printf 'HTTP/2 200\r\nstrict-transport-security: max-age=31536000\r\n' ;;
    *) printf 'HTTP/2 200\r\n' ;;
esac
exit 0
STUB
    chmod +x "$BATS_TEST_TMPDIR/httpin/curl"

    run env PATH="$BATS_TEST_TMPDIR/httpin:$PATH" bash "$PROBE" headers http://example.com
    assert_output --partial "HSTS on example.com"
    refute_output --partial "HSTS missing"
}

@test "a non-http scheme is refused before curl sees it" {
    # file://, gopher:// and dict:// would escape the external-target boundary.
    run bash "$PROBE" headers file:///etc/passwd
    [ "$status" -eq 2 ]
    assert_output --partial "only http and https targets are supported"

    run bash "$PROBE" files gopher://example.com
    [ "$status" -eq 2 ]

    run bash "$PROBE" cors dict://example.com
    [ "$status" -eq 2 ]
}

@test "a target given without a scheme is normalised, not mis-parsed" {
    run normalise_url app.example.com
    assert_output "https://app.example.com"

    run origin_of app.example.com
    assert_output "https://app.example.com:443"

    run origin_of //app.example.com/x
    assert_output "https://app.example.com:443"
}

@test "the probe script is executable" {
    run test -x "$PROBE"
    assert_success
}

@test "the probe script refuses to run without a command" {
    run bash "$PROBE"
    [ "$status" -eq 2 ]
    assert_output --partial "probe.sh headers"
}

@test "the probe script reports a missing argument with the documented exit" {
    run bash "$PROBE" headers
    [ "$status" -eq 2 ]
    assert_output --partial "FATAL"
    assert_output --partial "missing argument"
}

@test "the probe script refuses an unknown command" {
    run bash "$PROBE" exploit example.com
    [ "$status" -eq 2 ]
    assert_output --partial "unknown command"
}

@test "the probe script documents only the read-only checks" {
    run bash "$PROBE" --help
    assert_success
    assert_output --partial "headers"
    assert_output --partial "cors"
    assert_output --partial "redirect"
    assert_output --partial "files"
    assert_output --partial "ports"
    assert_output --partial "not a full sweep"
    refute_output --partial "PROBE_ORIGIN"
}
