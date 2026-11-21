#!/usr/bin/env bats
# =============================================================================
# src/agentic/self-improvement/tests/find_automation_candidates_tests.bats
# Guards the automation-discovery skill and its command: front matter, the
# docs.md manifest, the session-count contract, and that the command points at
# the skill instead of restating it.
# =============================================================================

setup() {
    bats_load_library bats-support
    bats_load_library bats-assert

    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
    SKILL="$MODULE_DIR/skills/find-automation-candidates/SKILL.md"
    SCRIPT="$MODULE_DIR/skills/find-automation-candidates/scripts/mine-commands.py"
    COMMAND="$MODULE_DIR/commands/find-automation-candidates.md"

    # Prose wraps: grep each assertion against one flattened line.
    FLAT="$BATS_TEST_TMPDIR/skill-flat.md"
    tr '\n' ' ' <"$SKILL" | tr -s ' ' >"$FLAT"
    CMD_FLAT="$BATS_TEST_TMPDIR/command-flat.md"
    tr '\n' ' ' <"$COMMAND" | tr -s ' ' >"$CMD_FLAT"
}

front_matter() {
    awk 'NR == 1 && /^---$/ { inside = 1; next } inside && /^---$/ { exit } inside { print }' "$1"
}

manifest_flow_list() {
    sed -n "s/^$1:[[:space:]]*\[\(.*\)\][[:space:]]*$/\1/p" "${MODULE_DIR}/docs.md" |
        tr ',' '\n' |
        sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^"//; s/"$//' |
        sed '/^$/d' |
        sort
}

disk_commands() {
    for path in "${MODULE_DIR}"/commands/*.md; do basename "$path" .md; done | sort
}

@test "the skill declares its front matter" {
    run front_matter "$SKILL"
    assert_output --partial "name: find-automation-candidates"
    assert_output --partial "description: "
}

@test "docs.md lists the skill and the command" {
    run manifest_flow_list skills
    assert_output --partial "find-automation-candidates"
    run diff -u <(disk_commands) <(manifest_flow_list commands)
    assert_success
}

@test "the command name matches its filename" {
    run front_matter "$COMMAND"
    assert_output --partial "name: devbot:find-automation-candidates"
    assert_output --partial "description: "
}

@test "the command points at the skill and restates none of its rules" {
    run grep -qF 'devbot:find-automation-candidates' "$CMD_FLAT"
    assert_success
    # Distinctive wording of the skill: a command that repeats it will not be
    # corrected when the skill changes.
    run grep -qiF 'heredoc' "$CMD_FLAT"
    assert_failure
    run grep -qiF 'pipeline' "$CMD_FLAT"
    assert_failure
}

@test "the command states the default session count instead of guessing" {
    run grep -qF '1000' "$CMD_FLAT"
    assert_success
    run grep -qiF 'do not guess' "$CMD_FLAT"
    assert_success
}

@test "the skill documents the session selection rule" {
    run grep -qiF 'v2' "$FLAT"
    assert_success
    run grep -qF '1000' "$FLAT"
    assert_success
    run grep -qiF 'tops up' "$FLAT"
    assert_success
}

@test "the skill requires a report file, its location and per-candidate intents" {
    run grep -qF 'report.md' "$FLAT"
    assert_success
    run grep -qiF 'absolute path' "$FLAT"
    assert_success
    run grep -qiF 'per-candidate intent' "$FLAT"
    assert_failure  # the template calls it an Intent section per candidate
    run grep -qiF '**Intent:**' "$FLAT"
    assert_success
}

@test "the miner defaults to 1000 sessions and exposes the stages" {
    run python3 "$SCRIPT" --help
    assert_success
    assert_output --partial "1000"
    assert_output --partial "extract"
    assert_output --partial "evaluate"
}

@test "the miner refuses an impossible session count" {
    run python3 "$SCRIPT" --sessions 0
    assert_failure
}
