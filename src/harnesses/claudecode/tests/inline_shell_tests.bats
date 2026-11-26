#!/usr/bin/env bats
# =============================================================================
# src/harnesses/claudecode/tests/inline_shell_tests.bats
# Guards the markdown this harness renders as a prompt before it runs it: a
# command or skill body must not contain the inline-shell directive. A code
# span that ends in an exclamation mark closes on that pair, the renderer runs
# the text after it as a shell command, and its stderr lands in the command the
# user ends up reading. OpenCode renders commands through the same pair, so the
# scan covers a source both harnesses load.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "${TEST_DIR}/../../../.." && pwd)"
}

# The two body kinds a harness renders: command files and skill instructions.
_find_bodies() {
  find "$1/src" \( -path '*/commands/*.md' -o -path '*/skills/*/SKILL.md' \) -type f
}

# Prints "file:line:content" for every bang a backtick follows directly.
_scan() {
  find "$1/src" \( -path '*/commands/*.md' -o -path '*/skills/*/SKILL.md' \) -type f \
    -exec grep -nF '!`' {} + 2>/dev/null
}

@test "no command or skill carries a bang directly before a backtick" {
  # 0 is matches (printed on failure), 1 is none; anything higher is a broken
  # scan, which must not read as a pass.
  run _scan "$PROJECT_ROOT"
  [ "$status" -le 1 ]
  assert_output ""
}

@test "the scan reaches the source tree" {
  # A scan that resolves to nothing is green and guards nothing.
  run _find_bodies "$PROJECT_ROOT"
  assert_success
  assert_output --partial 'src/agentic/dev/commands/full-review-loop.md'
}

@test "the scan reports a planted offender of either kind" {
  mkdir -p "${BATS_TEST_TMPDIR}/src/mod/commands" "${BATS_TEST_TMPDIR}/src/mod/skills/demo"
  printf 'carries no `fixup` commit\n' >"${BATS_TEST_TMPDIR}/src/mod/commands/clean.md"
  printf 'carries no `fixup!` commit\n' >"${BATS_TEST_TMPDIR}/src/mod/commands/offender.md"
  printf 'carries no `squash!` commit\n' >"${BATS_TEST_TMPDIR}/src/mod/skills/demo/SKILL.md"

  run _scan "$BATS_TEST_TMPDIR"
  assert_success
  assert_output --partial 'commands/offender.md:1:'
  assert_output --partial 'skills/demo/SKILL.md:1:'
  refute_output --partial 'commands/clean.md'
}
