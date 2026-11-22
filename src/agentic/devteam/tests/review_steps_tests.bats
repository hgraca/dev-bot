#!/usr/bin/env bats
# =============================================================================
# src/agentic/devteam/tests/review_steps_tests.bats
# Guards the review steps that close blind spots a review can otherwise carry:
# registration vs source, hand-maintained coverage lists, claims about existing
# mechanisms, unverifiable claims, exit-status semantics, working-directory
# scope, procedure described as enforcement, damage introduced while fixing,
# decision tables with unreachable states, and gates whose term is undefined.
#
# The wording must stay generic — technique a future reviewer can apply, not a
# post-mortem naming one codebase or one reviewing tool.
# =============================================================================

setup() {
    bats_load_library bats-support
    bats_load_library bats-assert

    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
    SKILL="${MODULE_DIR}/skills/review-implementation/SKILL.md"
    AGENT="${MODULE_DIR}/agents/reviewer.md"

    FLAT="$BATS_TEST_TMPDIR/skill-flat.md"
    tr '\n' ' ' <"$SKILL" | tr -s ' ' >"$FLAT"
}

@test "the skill carries every step it numbers, contiguously" {
    local step
    for step in \
        "Registration Completeness" \
        "Hand-Maintained Coverage Lists" \
        "Claims About Existing Mechanisms" \
        "Unverifiable Claims" \
        "Exit-Status Semantics" \
        "Working-Directory Scope" \
        "Procedure Described as Enforcement" \
        "Second-Order Damage While Fixing" \
        "Decision Tables and Retry Paths Cover Every Reachable State" \
        "A Conditional Gate Defines Its Term"; do
        run grep -qF "$step" "$SKILL"
        assert_success
    done
}

@test "each step states what to do, not just a subject" {
    # A heading with no instruction is a title, and a title catches nothing. The
    # step set is derived, never a literal window: a hand-maintained range let the
    # two steps this branch added escape it silently.
    local numbers expect n
    numbers="$(grep -oE '^### [0-9]+\.' "$SKILL" | grep -oE '[0-9]+' | sort -n)"
    # Derived, not assumed: the expected run starts at the file's own first step,
    # so a list numbered from 1 is checked as strictly as one numbered from 0.
    expect="$(seq "$(printf '%s\n' "$numbers" | head -1)" "$(printf '%s\n' "$numbers" | tail -1)")"
    [ "$numbers" = "$expect" ] || fail "step numbering is not contiguous: $(printf '%s' "$numbers" | tr '\n' ' ')"

    n="$(printf '%s\n' "$numbers" | wc -l | tr -d ' ')"
    [ "$n" -ge 26 ] || fail "expected at least 26 numbered steps, found $n"

    # Every step must carry at least one instruction, not just a heading.
    # Step 0 is one prose line by design, so the instruction check starts at 1.
    local empty
    empty="$(awk '
        /^### 0\. /{ t=""; b=0; next }
        /^### [0-9]+\./{ if (t != "" && b == 0) print t; t=$0; b=0; next }
        /^## /{ if (t != "" && b == 0) print t; t=""; next }
        /^- /{ if (t != "") b++ }
        END{ if (t != "" && b == 0) print t }
    ' "$SKILL")"
    [ -z "$empty" ] || fail "steps with no instruction: $empty"
}

@test "the registration step asks the question that catches a never-wired artifact" {
    run grep -qF 'would the suite stay green' "$FLAT"
    assert_success
}

@test "the coverage-list step flags the pattern, not only the omission" {
    run grep -qF 'literal list that must be edited with every addition is a latent blind spot' "$FLAT"
    assert_success
}

@test "the second-order step covers a replacement that matched nothing" {
    run grep -qF 'a replacement that silently matched nothing looks exactly like a successful edit' "$FLAT"
    assert_success
}

@test "the agent points at the steps instead of restating them" {
    run grep -qF 'devbot:review-implementation' "$AGENT"
    assert_success
    # The agent carries the habit; the numbered steps belong to the skill.
    run grep -qF 'Registration Completeness' "$AGENT"
    assert_failure
}

@test "the wording names no codebase, vendor or reviewing tool" {
    # Generic technique: a step that names one incident is not reusable. Scoped to
    # the eight steps — the rest of the file has its own legitimate examples.
    local block="${BATS_TEST_TMPDIR}/steps-block.md"
    awk '/^### 16\. /{inblock=1} /^## Recurring issue types/{inblock=0} inblock' "$SKILL" >"$block"
    [ -s "$block" ] || fail "the eight-step block was not found"

    local banned
    for banned in 'copilot' 'get-e' 'lbvd' 'pentest 2025' 'jira'; do
        run grep -qiF "$banned" "$block"
        assert_failure
    done
}
