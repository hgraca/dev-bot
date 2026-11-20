#!/usr/bin/env bats
# =============================================================================
# src/agentic/devteam/tests/review_steps_tests.bats
# Guards the review steps that close blind spots a review can otherwise carry:
# registration vs source, hand-maintained coverage lists, claims about existing
# mechanisms, unverifiable claims, exit-status semantics, working-directory
# scope, procedure described as enforcement, and damage introduced while fixing.
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

@test "the skill carries all eight steps" {
    local step
    for step in \
        "Registration Completeness" \
        "Hand-Maintained Coverage Lists" \
        "Claims About Existing Mechanisms" \
        "Unverifiable Claims" \
        "Exit-Status Semantics" \
        "Working-Directory Scope" \
        "Procedure Described as Enforcement" \
        "Second-Order Damage While Fixing"; do
        run grep -qF "$step" "$SKILL"
        assert_success
    done
}

@test "each step states what to do, not just a subject" {
    # A heading with no instruction is a title, and a title catches nothing.
    local n
    n="$(awk '/^### 1[6-9]\. |^### 2[0-3]\. /{c++} END{print c+0}' "$SKILL")"
    [ "$n" -eq 8 ] || fail "expected 8 numbered steps, found $n"

    # Every step must carry at least one instruction, not just a heading.
    local empty
    empty="$(awk '
        /^### 1[6-9]\. |^### 2[0-3]\. /{ if (t != "" && b == 0) print t; t=$0; b=0; next }
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
