#!/usr/bin/env bats
# =============================================================================
# src/agentic/dev/tests/docs-manifest_tests.bats
# Guards dev/docs.md: the manifest is the only source for the generated site, so
# a capability missing from it is invisible and one it names must resolve.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  DOCS="$MODULE_DIR/docs.md"
}

# Prints a frontmatter capability list as one sorted entry per line.
_list() {
  sed -n "s/^$1: \[\(.*\)\]$/\1/p" "$DOCS" | tr ',' '\n' \
    | sed 's/^ *"//; s/" *$//' | sed '/^$/d' | sort
}

@test "commands manifest matches the commands on disk" {
  expected="$(cd "$MODULE_DIR/commands" && ls -1 *.md 2>/dev/null | sed 's/\.md$//' | sort)"
  run _list commands
  assert_success
  [ "$output" = "$expected" ]
}

@test "skills manifest matches the skills the docs build sees" {
  # The generator globs skills/*/SKILL.md only, so the depth is deliberate.
  expected="$(cd "$MODULE_DIR/skills" && ls -1 */SKILL.md 2>/dev/null | sed 's|/SKILL.md$||' | sort)"
  run _list skills
  assert_success
  [ "$output" = "$expected" ]
}
