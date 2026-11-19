#!/usr/bin/env bats
# =============================================================================
# src/agentic/security/tests/security_tests.bats
# Contract for the security module: skill front matter, the docs.md capability
# manifest, and the content the external-pentest skill must carry.
# =============================================================================

setup() {
    bats_load_library bats-support
    bats_load_library bats-assert

    MODULE="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    PENTEST="${MODULE}/skills/pentest-external-webapp"
    SKILL="${PENTEST}/SKILL.md"
}

front_matter() {
    awk 'NR == 1 && /^---$/ { inside = 1; next } inside && /^---$/ { exit } inside { print }' "$1"
}

manifest_flow_list() {
    sed -n "s/^$1:[[:space:]]*\[\(.*\)\][[:space:]]*$/\1/p" "${MODULE}/docs.md" |
        tr ',' '\n' |
        sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^"//; s/"$//' |
        sed '/^$/d' |
        sort
}

disk_skills() {
    for path in "${MODULE}"/skills/*/; do basename "$path"; done | sort
}

@test "every skill declares valid front matter" {
    for path in "${MODULE}"/skills/*/SKILL.md; do
        name="$(basename "$(dirname "$path")")"
        run front_matter "$path"
        assert_output --partial "name: devbot:${name}"
        run grep -q '^description: ' "$path"
        assert_success
    done
}

@test "docs.md skills manifest matches the skill directories" {
    run diff -u <(disk_skills) <(manifest_flow_list skills)
    assert_success
}

@test "the pentest skill names the engagement shape it models" {
    run grep -qi 'external' "$SKILL"
    assert_success
    run grep -qi 'white-box' "$SKILL"
    assert_success
    run grep -qi 'intrusive' "$SKILL"
    assert_success
}

@test "the pentest skill gates every probe behind a written authorisation" {
    run grep -q 'authorisation gate' "$SKILL"
    assert_success
    run grep -q 'The authorisation is issued to you, not by you' "$SKILL"
    assert_success
    run grep -q 'Never test a host that is not named' "$SKILL"
    assert_success
    run grep -q 'Never change the identity, credential, or target' "$SKILL"
    assert_success
}

@test "the pentest skill documents all six phases in order" {
    local phases=(
        '### 1. Check'
        '### 2. Reconnaissance'
        '### 3. Vulnerability scanners'
        '### 4. Manual tests'
        '### 5. Intrusion'
        '### 6. Brute forcing'
    )
    local previous=0 phase line

    for phase in "${phases[@]}"; do
        line="$(grep -n "^${phase}$" "$SKILL" | head -1 | cut -d: -f1)"
        [ -n "$line" ] || fail "missing phase heading: $phase"
        [ "$line" -gt "$previous" ] || fail "phase out of order: $phase"
        previous="$line"
    done
}

@test "the pentest skill carries all seven checks the baseline evidenced" {
    local checks=(
        'Role authorisation and IDOR'
        'CORS origin reflection with credentials'
        'Open redirect'
        'HSTS and HTTPS enforcement'
        'Unauthenticated access to an owned resource'
        'Publicly readable configuration and metadata files'
        'Unnecessary open ports'
    )
    local check

    for check in "${checks[@]}"; do
        run grep -qF "$check" "$SKILL"
        assert_success
    done
}

@test "every documented check states what passing looks like" {
    # Seven checks, each with a Pass and a Fail line: no check may be listed
    # without a verdict a tester can apply.
    local passes fails
    passes="$(grep -c '^- \*\*Pass:\*\*' "$SKILL")"
    fails="$(grep -c '^- \*\*Fail:\*\*' "$SKILL")"

    [ "$passes" -ge 7 ] || fail "only $passes checks state a pass criterion"
    [ "$fails" -eq "$passes" ] || fail "$passes pass criteria but $fails fail criteria"
}

@test "the pentest skill carries the CVSS 3.1 classification bands" {
    local band
    for band in '9.0–10.0' '7.0–8.9' '4.0–6.9' '0.1–3.9'; do
        run grep -qF "$band" "$SKILL"
        assert_success
    done
    run grep -qF 'Informational' "$SKILL"
    assert_success
}

@test "the pentest skill carries the report's finding record and reports the regression" {
    local field
    for field in '**ID:**' '**CVSS:**' '**Targets:**' '**Finding:**' '**Result:**' \
        '**Proof of concept:**' '**Recommendation:**' '**Evidence:**'; do
        run grep -qF "$field" "$SKILL"
        assert_success
    done
    run grep -qF 'Regression verdict' "$SKILL"
    assert_success
}

@test "the pentest skill's references exist and carry their baseline" {
    run test -s "${PENTEST}/references/wstg-checklist.md"
    assert_success
    run grep -qF 'WSTG-ATHZ' "${PENTEST}/references/wstg-checklist.md"
    assert_success
    run grep -qF 'WSTG-APIT' "${PENTEST}/references/wstg-checklist.md"
    assert_success
    # The API Top 10 is a different document from the WSTG and is cited as one.
    run grep -qF 'OWASP API Security Top 10' "${PENTEST}/references/wstg-checklist.md"
    assert_success
    # The baseline records no engagement data: no hosts, endpoints or identifiers.
    run bash -c "tr '\n' ' ' <'${PENTEST}/references/regression-external-baseline.md' | grep -q 'deliberately.*not.*recorded here'"
    assert_success

    run test -s "${PENTEST}/references/regression-external-baseline.md"
    assert_success
    for finding in 4.1 4.2 4.3 4.4 4.5 5.1 5.2; do
        run grep -qF "## ${finding} —" "${PENTEST}/references/regression-external-baseline.md"
        assert_success
    done
}

@test "the checklist marks the rows that need intrusive permission" {
    run grep -qF '**invasive**' "${PENTEST}/references/wstg-checklist.md"
    assert_success
    # The marker must be defined as well as used, or a reader cannot act on it.
    # Flatten first: prettier reflows the sentence across lines.
    run bash -c "tr '\n' ' ' <'${PENTEST}/references/wstg-checklist.md' | grep -q 'invasive.*record it as untested'"
    assert_success
}

@test "the regression reference gives every finding a verdict path" {
    run grep -qF 'Resolved when:' "${PENTEST}/references/regression-external-baseline.md"
    assert_success
    # Seven findings, seven resolution criteria — no finding left without one.
    local criteria
    criteria="$(grep -c 'Resolved when:' "${PENTEST}/references/regression-external-baseline.md")"
    [ "$criteria" -eq 7 ] || fail "expected 7 resolution criteria, found $criteria"
}

@test "the pentest skill points at its probe script and the static counterpart" {
    run grep -qF 'scripts/probe.sh' "$SKILL"
    assert_success
    run grep -qF 'devbot:audit-security' "$SKILL"
    assert_success
}
