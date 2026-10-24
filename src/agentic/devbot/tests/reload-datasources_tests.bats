#!/usr/bin/env bats
# =============================================================================
# src/agentic/devbot/tests/reload-datasources_tests.bats
# Guards the reload-datasources command's contract: it runs the subcommand this
# repository ships, tells the agent how to read the outcome, and never falls
# back to the restart it exists to replace.
# =============================================================================

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  COMMAND="$MODULE_DIR/commands/reload-datasources.md"
  # Prose wraps: grep each assertion against one flattened line.
  FLAT="$BATS_TEST_TMPDIR/command-flat.md"
  tr '\n' ' ' < "$COMMAND" | tr -s ' ' > "$FLAT"
}

@test "command frontmatter names devbot:reload-datasources" {
  run sed -n '1,4p' "$COMMAND"
  [ "$status" -eq 0 ]
  [[ "$output" == *"name: devbot:reload-datasources"* ]]
}

@test "command runs the reload subcommand this repository ships" {
  grep -q 'devbot datasources reload' "$COMMAND"
  # The verb is registered in bin/devbot, not invented by the command.
  grep -q 'cmd_datasources' "$MODULE_DIR/../../../bin/devbot"
}

@test "command tells the agent how to read each outcome" {
  grep -qi 'every selected source is served' "$FLAT"
  grep -qi 'is published but does not answer' "$FLAT"
  grep -qi 'selected but still unpublishable' "$FLAT"
  grep -qi 'another live project selects what is still unpublishable' "$FLAT"
}

@test "command forbids the restart it exists to replace — except for a stale manifest" {
  grep -qi 'do not restart the harness or the session to recover an ordinary datasource' "$FLAT"
  grep -qi 'stale-manifest failure is the exception' "$FLAT"
  grep -qi 'devbot reinit' "$FLAT"
}

@test "command keeps the evaluate-once contract" {
  grep -qi 'evaluates the catalogue once, at boot' "$FLAT"
  grep -qi 'nothing runs in the background' "$FLAT"
}
