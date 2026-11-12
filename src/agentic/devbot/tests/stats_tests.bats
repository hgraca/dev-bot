#!/usr/bin/env bats
# =============================================================================
# src/agentic/devbot/tests/stats_tests.bats
# Guards the stats command's contract: it targets the harness actually running,
# forwards its arguments to `devbot stats`, and answers in exactly three
# sections of one-line bullets.
# =============================================================================

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  COMMAND="$MODULE_DIR/commands/stats.md"
  # Prose wraps: grep each assertion against one flattened line.
  FLAT="$BATS_TEST_TMPDIR/command-flat.md"
  tr '\n' ' ' < "$COMMAND" | tr -s ' ' > "$FLAT"
}

@test "command frontmatter names devbot:stats" {
  run sed -n '1,4p' "$COMMAND"
  [ "$status" -eq 0 ]
  [[ "$output" == *"name: devbot:stats"* ]]
}

@test "command runs the stats subcommand this repository ships" {
  grep -q 'devbot stats' "$COMMAND"
  # The verb is registered in bin/devbot, not invented by the command.
  grep -q 'cmd_stats' "$MODULE_DIR/../../../bin/devbot"
}

@test "command translates the request into CLI flags" {
  grep -q '\$ARGUMENTS' "$COMMAND"
  grep -qi 'translate the request' "$FLAT"
  grep -q -- '--days=N' "$COMMAND"
  grep -q -- '--project=<dir>' "$COMMAND"
}

@test "command keeps the detected harness authoritative" {
  grep -qi 'detected harness is authoritative' "$FLAT"
  grep -qi 'pass it explicitly' "$FLAT"
  grep -qi 'ignore any' "$FLAT"
  # The invocation must not append raw arguments after the detected flag.
  ! grep -Eq 'devbot stats --harness=<detected> \$' "$FLAT"
}

@test "command targets the harness actually running" {
  grep -q -- '--harness' "$COMMAND"
  grep -q 'opencode names MCP tools' "$FLAT"
  grep -q 'mcp__<server>__<tool>' "$COMMAND"
  grep -qi 'cross-check' "$FLAT"
  # No naming signal when MCP is off: fall back to the config key.
  grep -qi 'fallback when no MCP tools are exposed' "$FLAT"
}

@test "command names exactly the three requested sections" {
  grep -q '^### Working well' "$COMMAND"
  grep -q '^### Can be improved' "$COMMAND"
  grep -q '^### Not working at all' "$COMMAND"
  [ "$(grep -c '^### ' "$COMMAND")" -eq 3 ]
}

@test "command separates guaranteed sections from conditional ones" {
  grep -qi 'always present' "$FLAT"
  grep -qi 'a missing one means no data' "$FLAT"
}

@test "command takes the enabled server set from the harness config" {
  grep -qi 'enabled set from the selected harness config' "$FLAT"
  grep -q 'mcpServers' "$COMMAND"
  grep -qi 'out of scope, not broken' "$FLAT"
}

@test "command does not read Never used as a call count" {
  grep -qi 'grade-matrix bucket' "$FLAT"
  grep -qi 'not proof of zero' "$FLAT"
  grep -qi 'had no calls in the window' "$FLAT"
}

@test "command pairs each improvement with a one-line suggestion" {
  grep -q 'one-line suggestion' "$FLAT"
  grep -q '→ <what to change>' "$COMMAND"
}

@test "command instructs one-line bullets of at most 72 characters" {
  grep -q 'single line of at most 72 characters' "$FLAT"
}
