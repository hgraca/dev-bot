#!/usr/bin/env bats
# =============================================================================
# src/agentic/self-improvement/tests/create_command_tests.bats
# Guards the command-authoring skill: its own front matter, the docs.md manifest,
# the rules that must not drift out of it, and that create-devbot-module points
# at it instead of carrying its own copy of those rules.
# =============================================================================

setup() {
    bats_load_library bats-support
    bats_load_library bats-assert

    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
    SKILL="$MODULE_DIR/skills/create-command/SKILL.md"
    MODULE_SKILL="$MODULE_DIR/skills/create-devbot-module/SKILL.md"

    # Prose wraps: grep each assertion against one flattened line.
    FLAT="$BATS_TEST_TMPDIR/skill-flat.md"
    tr '\n' ' ' <"$SKILL" | tr -s ' ' >"$FLAT"
    MODULE_FLAT="$BATS_TEST_TMPDIR/module-flat.md"
    tr '\n' ' ' <"$MODULE_SKILL" | tr -s ' ' >"$MODULE_FLAT"
}

front_matter() {
    awk 'NR == 1 && /^---$/ { inside = 1; next } inside && /^---$/ { exit } inside { print }' "$1"
}

disk_skills() {
    for path in "${MODULE_DIR}"/skills/*/; do basename "$path"; done | sort
}

manifest_flow_list() {
    sed -n "s/^$1:[[:space:]]*\[\(.*\)\][[:space:]]*$/\1/p" "${MODULE_DIR}/docs.md" |
        tr ',' '\n' |
        sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^"//; s/"$//' |
        sed '/^$/d' |
        sort
}

@test "the skill declares its front matter" {
    run front_matter "$SKILL"
    assert_output --partial "name: devbot:create-command"
    run grep -q '^description: ' "$SKILL"
    assert_success
}

@test "docs.md skills manifest matches the skill directories" {
    run diff -u <(disk_skills) <(manifest_flow_list skills)
    assert_success
}

@test "the skill states the name/filename rule and why it matters" {
    run grep -qF 'name: devbot:<id>' "$FLAT"
    assert_success
    run grep -qiF 'must match' "$FLAT"
    assert_success
    run grep -qF '_link_commands' "$FLAT"
    assert_success
}

@test "the skill covers the argument contract" {
    run grep -qF '$ARGUMENTS' "$FLAT"
    assert_success
    run grep -qiF 'ask, and wait' "$FLAT"
    assert_success
    # A command that guesses the subject is the failure this line exists to stop.
    run grep -qF 'guesses the user' "$FLAT"
    assert_success
}

@test "the skill carries the reference-don't-restate rule" {
    run grep -qF 'Never restate a skill' "$FLAT"
    assert_success
    run grep -qF 'devbot:create-skill' "$FLAT"
    assert_success
}

@test "the skill covers wiring, the docs manifest and the inventory" {
    run grep -qF 'devbot init' "$FLAT"
    assert_success
    run grep -qF 'commands: [' "$FLAT"
    assert_success
    run grep -qF 'devbot list commands' "$FLAT"
    assert_success
}

@test "create-devbot-module points at the command skill" {
    run grep -qF 'devbot:create-command' "$MODULE_FLAT"
    assert_success
}

@test "create-devbot-module no longer carries its own copy of the command rules" {
    # The rules moved: a second copy is what the reference exists to prevent.
    run grep -qiF 'Format as markdown with clear procedure steps' "$MODULE_FLAT"
    assert_failure
    run grep -qiF 'Commands go under' "$MODULE_FLAT"
    assert_failure
}

@test "create-devbot-module keeps the interview the extraction must not drop" {
    # The extraction moved the rules; the elicitation stays with the module question.
    run grep -qF 'What is the command name?' "$MODULE_FLAT"
    assert_success
    run grep -qF 'What does the command do?' "$MODULE_FLAT"
    assert_success
    run grep -qF 'Does it have another command?' "$MODULE_FLAT"
    assert_success
}

@test "the skill states the single-value argument contract and the farm's gap" {
    run grep -qF '`$1` is the first word' "$FLAT"
    assert_success
    # The farm does not prune, and a skill that claims otherwise misleads.
    run grep -qF 'It does not prune' "$FLAT"
    assert_success
}
