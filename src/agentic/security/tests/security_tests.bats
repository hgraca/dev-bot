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
    AUDIT="${MODULE}/skills/audit-security/SKILL.md"
    FINDINGS="${MODULE}/skills/security-findings/SKILL.md"
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

# Derived from the table, not a hardcoded ten.
# An OWASP revision changes what is expected.
owasp_categories() {
    grep -oE '^\| A[0-9]{2} \|' "${AUDIT}" | grep -oE 'A[0-9]{2}' | sort -u
}

# Check counts for EVERY `#### A0n — ` section, one line per section.
# A category can appear more than once (A01 three times), and validating only
# the first would leave the rest unguarded.
checklist_sections() {
    awk -v prefix="#### $1 — " '
        index($0, prefix) == 1 { if (inside) print count; inside = 1; count = 0; next }
        inside && substr($0, 1, 3) == "###" { print count; inside = 0; next }
        inside && /^- \[ \]/ { count++ }
        END { if (inside) print count }
    ' "${AUDIT}"
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

@test "both skills score through the shared record" {
    local skill
    for skill in "$AUDIT" "$SKILL"; do
        run grep -qF 'devbot:security-findings' "$skill"
        assert_success
        run grep -qF 'CVSS v4.0' "$skill"
        assert_success
    done
}

@test "no security artefact ships a superseded CVSS vector" {
    # The vector form, everywhere it could be written — skills, references and
    # commands. Excludes the test files, which contain the literal by design.
    # The regression baseline carried five of these past an earlier version of
    # this test that scanned one spelling of one directory.
    run bash -c "grep -rlF 'CVSS:3.1' '${MODULE}' | grep -v '/tests/' || true"
    [ -z "$output" ] || fail "still ships a CVSS 3.1 vector: $output"
}

@test "the security agent names no superseded CVSS version" {
    # The producer's own scoring instruction: the place a runtime finding is
    # actually graded, and outside the module tree a skills-only scan reaches.
    ROOT="$(cd "${MODULE}/../../.." && pwd)"
    run bash -c "grep -nE 'CVSS[ :]3\\.1' '${ROOT}/src/agentic/devteam/agents/security.md' || true"
    [ -z "$output" ] || fail "security agent still names CVSS 3.1: $output"
}

@test "the pentest skill points at the shared record and keeps the regression verdict" {
    run grep -qF 'devbot:security-findings' "$SKILL"
    assert_success
    run grep -qF 'Regression verdict' "$SKILL"
    assert_success
    # The record lives in one place now; a field list here is the drift
    # PDR 20261024080246 forbids.
    local field
    for field in '**ID:**' '**CVSS:**' '**Targets:**' '**Evidence:**' '**Recommendation:**'; do
        run grep -qF "$field" "$SKILL"
        assert_failure
    done
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

@test "the pentest skill names what it is attacking before the checklist" {
    run grep -qF '## What you are attacking' "$SKILL"
    assert_success
    local fact
    for fact in '| Asset' '| Attacker' '| Boundary'; do
        run grep -qF "$fact" "$SKILL"
        assert_success
    done
}

@test "the pentest skill labels the seven checks as a sample" {
    run bash -c "tr '\n' ' ' <'${SKILL}' | grep -qi 'a sample, not a taxonomy'"
    assert_success
}

@test "the pentest skill separates what needs no authorisation from what does" {
    run grep -qF '## Before there is an engagement' "$SKILL"
    assert_success
    # A source reading is a lower evidence tier, and the section must say so.
    run grep -qF 'read-in-source' "$SKILL"
    assert_success
}

# --- OWASP Top 10:2025 ------------------------------------------------------

@test "the audit skill answers the OWASP 2025 list" {
    local category
    for category in A01 A02 A03 A04 A05 A06 A07 A08 A09 A10; do
        run grep -qF "| ${category} |" "$AUDIT"
        assert_success
    done
    # The categories a 2021 checklist carries under a different number or scope.
    run grep -qF 'Software Supply Chain' "$AUDIT"
    assert_success
    run grep -qF 'Insecure Design' "$AUDIT"
    assert_success
    run grep -qF 'Mishandling of Exceptional Conditions' "$AUDIT"
    assert_success
}

@test "the OWASP table pairs each changed category with its number" {
    # A table with A03 and A06 swapped would satisfy a names-only assertion.
    run grep -qF '| A03 | **Software Supply Chain Failures**' "$AUDIT"
    assert_success
    run grep -qF '| A06 | **Insecure Design**' "$AUDIT"
    assert_success
    run grep -qF '| A10 | **Mishandling of Exceptional Conditions**' "$AUDIT"
    assert_success
}

@test "every OWASP category in the table carries a checklist section" {
    # A04 was missing and nothing failed, so §3's claim
    # went unverified. This makes an omission red, not invisible.
    local categories category
    categories="$(owasp_categories)"
    # A broken table parse would make the loop vacuous and the test green for
    # the wrong reason.
    [ "$(printf '%s\n' "${categories}" | wc -l)" -ge 10 ] ||
        fail "expected the ten OWASP categories, parsed: ${categories}"
    for category in ${categories}; do
        grep -qE "^#### ${category} — " "${AUDIT}" ||
            fail "${category} has a table row but no checklist section"
    done
}

@test "every checklist section carries checks, not just a heading" {
    # A heading with nothing under it satisfies a heading-only guard — which is
    # how a category can look mapped and still be unexamined. Every section, not
    # just the first: A01 appears three times.
    local categories category counts n
    categories="$(owasp_categories)"
    for category in ${categories}; do
        counts="$(checklist_sections "${category}")"
        [ -n "${counts}" ] || fail "${category} has a table row but no checklist section"
        while IFS= read -r n; do
            [ "${n}" -ge 3 ] ||
                fail "${category} has a section carrying ${n} check(s) — a heading is not a checklist"
        done <<<"${counts}"
    done
}

@test "neither skill answers a superseded OWASP list" {
    local skill
    for skill in "$AUDIT" "$SKILL"; do
        run grep -qF '2017' "$skill"
        assert_failure
        run grep -qF 'Priority Order' "$skill"
        assert_failure
    done
    # The old list gave XSS and SSRF their own numbered categories; 2025 folds
    # them into A05 and A01. Naming them is fine, listing them is the drift.
    run grep -qF '**SSRF**' "$AUDIT"
    assert_failure
    run grep -qF '**XSS**' "$AUDIT"
    assert_failure
}

@test "the audit skill states exit criteria it can be held to" {
    # Borrowed from the pentest skill: a section with no exit criterion cannot
    # say when it is done, so a partial review reads as a complete one.
    local criteria
    criteria="$(grep -c '^\*\*Exit:\*\*' "$AUDIT")"
    [ "$criteria" -ge 3 ] || fail "expected at least 3 exit criteria, found $criteria"
}

@test "the audit skill requires coverage and a re-audit verdict" {
    run grep -qF '## 7. Coverage' "$AUDIT"
    assert_success
    local result
    for result in checked clean 'not applicable' 'not examined'; do
        run grep -qF "\`${result}\`" "$AUDIT"
        assert_success
    done
    local verdict
    for verdict in 'Resolved' 'Still open' 'Partially resolved' 'Not retestable'; do
        run grep -qF "**${verdict}**" "$AUDIT"
        assert_success
    done
}

@test "the audit skill treats a scan hit as a candidate, not a finding" {
    run grep -qF 'candidate generators' "$AUDIT"
    assert_success
    run bash -c "tr '\n' ' ' <'${AUDIT}' | grep -qi 'a hit is not a finding'"
    assert_success
    local step
    for step in 'Reachability' 'Guard' 'Evidence'; do
        run grep -qF "**${step}**" "$AUDIT"
        assert_success
    done
}

@test "the pentest skill names the FOSS tooling façade" {
    run grep -qF 'scripts/tooling.sh' "$SKILL"
    assert_success
    local tool
    for tool in '`zap`' '`nuclei`' '`ffuf`'; do
        run grep -qF "$tool" "$SKILL"
        assert_success
    done
    # The ledger half: an absent tool is a skipped check, not a pass.
    run grep -qF 'skipped: tool absent' "$SKILL"
    assert_success
}

@test "the audit skill routes its semantic scans through the façade" {
    run grep -qF 'scripts/tooling.sh' "$AUDIT"
    assert_success
    local tool
    for tool in semgrep gitleaks trivy; do
        run grep -qF "\`${tool}\`" "$AUDIT"
        assert_success
    done
}

@test "the module ships executable lifecycle scripts for its tooling" {
    local script
    for script in install.sh update.sh scripts/tooling.sh; do
        run test -x "${MODULE}/${script}"
        assert_success
    done
}

@test "the findings skill ships a store and a gate" {
    run grep -qF 'findings.sh' "$FINDINGS"
    assert_success
    run grep -qF '## The gate' "$FINDINGS"
    assert_success
    run test -x "${MODULE}/scripts/findings.sh"
    assert_success
}

@test "both producing skills write to the store, not only the report" {
    local skill
    for skill in "$AUDIT" "$SKILL"; do
        run grep -qF 'findings.sh add' "$skill"
        assert_success
    done
}

# --- security-findings ------------------------------------------------------

@test "the findings skill carries every field of the record" {
    local field
    for field in '**ID:**' '**Title:**' '**Severity:**' '**CVSS:**' '**Tier:**' \
        '**Finding:**' '**Result:**' '**Evidence:**' '**Status:**' '**Discovered:**' \
        '**Location:**' '**Targets:**' '**Proof of concept:**' '**Recommendation:**' \
        '**References:**' '**Coverage basis:**'; do
        run grep -qF "$field" "$FINDINGS"
        assert_success
    done
}

@test "the findings skill carries every lifecycle state" {
    local state
    for state in open confirmed mitigated false_positive accepted_risk; do
        run grep -qF "\`${state}\`" "$FINDINGS"
        assert_success
    done
    # The monotonic guard is the rule that makes the lifecycle worth having.
    run bash -c "tr '\n' ' ' <'${FINDINGS}' | grep -qi 'dismissal never erases'"
    assert_success
}

@test "the findings skill scores with CVSS v4.0 and not 3.1" {
    run grep -qF 'CVSS v4.0' "$FINDINGS"
    assert_success
    run grep -qF 'CVSS:4.0/' "$FINDINGS"
    assert_success
    # A 3.1 vector in the skill that owns the scheme is the drift this exists to stop.
    run grep -qF 'CVSS:3.1' "$FINDINGS"
    assert_failure
    local band
    for band in '9.0–10.0' '7.0–8.9' '4.0–6.9' '0.1–3.9'; do
        run grep -qF "$band" "$FINDINGS"
        assert_success
    done
}

@test "the findings skill fixes the refutation verdicts" {
    local verdict
    for verdict in uphold downgrade reject unverifiable; do
        run grep -qF "\`${verdict}\`" "$FINDINGS"
        assert_success
    done
}

@test "the findings skill defines the report shape both siblings emit" {
    local section
    for section in 'Scope and basis' 'Coverage' 'Findings' 'Refutation' 'Summary' \
        'Positive findings'; do
        run grep -qF "**${section}**" "$FINDINGS"
        assert_success
    done
}

@test "the findings skill names its siblings instead of restating them" {
    # PDR 20261024080246: a referencing skill names the other and when to load it.
    run grep -qF 'devbot:audit-security' "$FINDINGS"
    assert_success
    run grep -qF 'devbot:pentest-external-webapp' "$FINDINGS"
    assert_success
    local restated
    for restated in 'Spoofing' 'WSTG-' '### 1. Check' 'seven checks'; do
        run grep -qiF "$restated" "$FINDINGS"
        assert_failure
    done
}

# --- commands ---------------------------------------------------------------

disk_commands() {
    for path in "${MODULE}"/commands/*.md; do basename "$path" .md; done | sort
}

@test "every command declares valid front matter" {
    for path in "${MODULE}"/commands/*.md; do
        name="$(basename "$path" .md)"
        run front_matter "$path"
        assert_output --partial "name: devbot:${name}"
        run grep -q '^description: ' "$path"
        assert_success
    done
}

@test "docs.md commands manifest matches the command files" {
    run diff -u <(disk_commands) <(manifest_flow_list commands)
    assert_success
}

@test "the pentest command resolves its project instead of assuming one" {
    local cmd="${MODULE}/commands/pentest-webapp.md"
    run bash -c "tr '\n' ' ' <'$cmd' | grep -q 'ask which project to test and wait'"
    assert_success
    # A path is resolved, and an unregistered one is a refusal, not a fallback.
    run grep -qF 'project-for-path' "$cmd"
    assert_success
    run grep -qF 'Exit `3`' "$cmd"
    assert_success
    run grep -qF 'list-projects' "$cmd"
    assert_success
    # One value, so $1 — not the whole tail.
    run grep -qF '`$1`' "$cmd"
    assert_success
    # A bare name through project-for-path resolves against the cwd, silently.
    run bash -c "tr '\n' ' ' <'$cmd' | grep -q 'Never hand a bare name to'"
    assert_success
    # The ambiguity is settled before the two branches, or the ordered bullets
    # make "ask when both" unreachable.
    run bash -c "tr '\n' ' ' <'$cmd' | grep -q 'Decide the ambiguity first'"
    assert_success
}

@test "the pentest command loads the project memory and the skill" {
    local cmd="${MODULE}/commands/pentest-webapp.md"
    run grep -qF 'project-memory' "$cmd"
    assert_success
    run grep -qF 'devbot:pentest-external-webapp' "$cmd"
    assert_success
}

@test "the pentest command points at the skill instead of restating it" {
    local cmd="${MODULE}/commands/pentest-webapp.md"
    # It must send the reader to the skill's gate...
    run bash -c "tr '\n' ' ' <'$cmd' | grep -q 'authorisation gate is a hard stop'"
    assert_success
    # ...without re-listing what the gate asks, or the skill's own structure.
    local restated
    for restated in 'in-scope hosts' 'credentials issued' 'intrusive testing' \
        'lockout' 'time box' 'WSTG' 'CVSS' 'seven checks' 'six phases' \
        'issued to you, not by you' 'never draft one, infer one'; do
        run grep -qiF "$restated" "$cmd"
        assert_failure
    done
}

@test "the pentest command offers the report rather than writing it" {
    local cmd="${MODULE}/commands/pentest-webapp.md"
    run bash -c "tr '\n' ' ' <'$cmd' | grep -q 'offer.*to save it'"
    assert_success
    # The vault path is configurable, and commit_memory is the signal that decides
    # whether writing it commits a pentest report into the repository.
    run grep -qF 'devbot_dir' "$cmd"
    assert_success
    run grep -qF 'commit_memory' "$cmd"
    assert_success
    # The setting is intent; check-ignore on the file is the fact, and its exit 0
    # means ignored — the inverted reading is the trap.
    run grep -qF 'Exit `0` means ignored' "$cmd"
    assert_success
}
