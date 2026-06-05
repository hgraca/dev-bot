#!/usr/bin/env bats
# =============================================================================
# bin/tests/commands_tests.bats
# Tests for `devbot list <type>` — the agentic-artifact listing subcommand.
#
# Validates that:
#   - Each type (commands, agents, skills, hooks, mcps, tools) emits a
#     well-formed markdown table with aligned columns
#   - Types with descriptions (commands/agents/skills) include a Description
#     column; types without (hooks/mcps/tools) omit it
#   - The -a/--all flag is accepted (and --help / unknown args handled)
#   - Artifacts from disabled modules are excluded by default, included with --all
# =============================================================================

setup() {
  load "$(npm root -g)/bats-support/load.bash"
  load "$(npm root -g)/bats-assert/load.bash"

  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  command -v python3 &>/dev/null || skip "python3 not installed"
}

# Validate a markdown table: header present, separator row, and aligned pipes.
# $1 = expected number of columns (2 or 3)
assert_well_formed_table() {
  python3 -c "
import sys, re
expected = int(sys.argv[1])
lines = sys.stdin.read().splitlines()
assert len(lines) >= 3, 'expected at least header, separator, and one row'
# every row has exactly expected+1 pipe delimiters
for i, l in enumerate(lines):
    n = l.count('|')
    assert n == expected + 1, f'row {i}: expected {expected+1} pipes, got {n}: {l!r}'
assert re.fullmatch(r'[| -]+', lines[1]), f'bad separator row: {lines[1]!r}'
positions = {tuple(i for i, c in enumerate(l) if c == '|') for l in lines}
assert len(positions) == 1, f'misaligned pipes: {positions}'
" "$1" <<< "$output"
}

@test "devbot list commands emits a table with a Description column" {
  run bash "$PROJECT_ROOT/bin/devbot" list commands
  [ "$status" -eq 0 ]

  assert_output --partial "| Command"
  assert_output --partial "| Description"
  assert_output --partial "| create-codebase-report"
  assert_output --partial "| fix-slow-queries"

  assert_well_formed_table 3
}

@test "devbot list agents emits a table with a Type and Description column" {
  run bash "$PROJECT_ROOT/bin/devbot" list agents
  [ "$status" -eq 0 ]

  assert_output --partial "| Agent"
  assert_output --partial "| Type"
  assert_output --partial "| Description"
  assert_output --partial "| TeamLead"
  assert_output --partial "| Architect"
  assert_output --partial "| primary"
  assert_output --partial "| subagent"

  assert_well_formed_table 4

  # primary rows must sort ahead of subagent rows within each module
  python3 -c "
import sys
lines = sys.stdin.read().splitlines()[2:]  # skip header + separator
seen_subagent = {}
for line in lines:
    cells = [c.strip() for c in line.split('|')[1:-1]]
    module, agent, typ = cells[0], cells[1], cells[2]
    if typ == 'subagent':
        seen_subagent[module] = True
    elif typ == 'primary':
        assert module not in seen_subagent, f'primary appears after subagent in module {module}'
" <<< "$output"
}

@test "devbot list skills emits a table with a Description column" {
  run bash "$PROJECT_ROOT/bin/devbot" list skills
  [ "$status" -eq 0 ]

  assert_output --partial "| Skill"
  assert_output --partial "| Description"
  assert_output --partial "| git-report"
  assert_output --partial "| make-plan"

  assert_well_formed_table 3
}

@test "devbot list hooks emits a table without a Description column" {
  run bash "$PROJECT_ROOT/bin/devbot" list hooks
  [ "$status" -eq 0 ]

  assert_output --partial "| Hook"
  refute_output --partial "| Description"
  assert_output --partial "on-tool_execute_before-guards"

  assert_well_formed_table 2
}

@test "devbot list mcps emits a table without a Description column" {
  run bash "$PROJECT_ROOT/bin/devbot" list mcps
  [ "$status" -eq 0 ]

  assert_output --partial "| MCP"
  refute_output --partial "| Description"
  assert_output --partial "| qmd"

  assert_well_formed_table 2
}

@test "devbot list tools emits a table with a Description column" {
  run bash "$PROJECT_ROOT/bin/devbot" list tools
  [ "$status" -eq 0 ]

  assert_output --partial "| Tool"
  assert_output --partial "| Description"
  assert_output --partial "| git-report"
  assert_output --partial "| tree"
  assert_output --partial "| qmd"
  assert_output --partial "Format markdown files with consistent formatting via prettier"
  # tools not wired into .agents/tools/ (not tools-mcp tools) are excluded
  refute_output --partial "| graphify"
  refute_output --partial "start-graphify-mcp"

  assert_well_formed_table 3
}

@test "devbot list accepts -a and --all" {
  run bash "$PROJECT_ROOT/bin/devbot" list commands -a
  [ "$status" -eq 0 ]
  assert_output --partial "| Command"

  run bash "$PROJECT_ROOT/bin/devbot" list commands --all
  [ "$status" -eq 0 ]
  assert_output --partial "| Command"
}

@test "devbot list --help prints usage" {
  run bash "$PROJECT_ROOT/bin/devbot" list --help
  [ "$status" -eq 0 ]
  assert_output --partial "Usage: devbot list"
  assert_output --partial "--all"
}

@test "devbot list rejects unknown flags and unknown types" {
  run bash "$PROJECT_ROOT/bin/devbot" list commands --bogus
  [ "$status" -ne 0 ]
  assert_output --partial "Unknown argument"

  run bash "$PROJECT_ROOT/bin/devbot" list bogus-type
  [ "$status" -ne 0 ]
  assert_output --partial "Unknown type"
}

@test "devbot list excludes disabled modules by default and includes them with --all" {
  # `aws` is a globally-disabled module that ships mcps/tools/skills.
  run bash "$PROJECT_ROOT/bin/devbot" list mcps
  [ "$status" -eq 0 ]
  refute_output --partial "| aws-mcp"

  run bash "$PROJECT_ROOT/bin/devbot" list mcps --all
  [ "$status" -eq 0 ]
  assert_output --partial "| aws-mcp"
}
