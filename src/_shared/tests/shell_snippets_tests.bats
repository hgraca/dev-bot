#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/shell_snippets_tests.bats
# The managed shell-block helpers a tool module uses to own a shell FUNCTION:
#
#   _devbot_shell_block_upsert   — replace devbot's marked block, append if absent
#   _devbot_shell_function_strip — remove a foreign definition of the function
#
# The property that matters: an install/update re-renders the block from its
# source, so a changed function reaches the machine; a definition devbot did not
# write is removed first, so the shell never runs two versions.
#
# Run from project root:
#   bats src/_shared/tests/shell_snippets_tests.bats
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
  PROJECT_ROOT="$(cd "${TEST_DIR}/../../.." && pwd)"
  RC="${BATS_TEST_TMPDIR}/rc"

  source "${PROJECT_ROOT}/src/_shared/functions.sh"
}

# ── block upsert ─────────────────────────────────────────────────────────────

@test "upsert appends a marked block to an existing rc" {
  printf '%s\n' 'export PATH="$HOME/bin:$PATH"' >"${RC}"

  _devbot_shell_block_upsert "${RC}" demo <<'EOF'
demo() { echo one; }
EOF

  run cat "${RC}"
  assert_line --index 0 'export PATH="$HOME/bin:$PATH"'
  assert_output --partial "# >>> devbot:demo >>>"
  assert_output --partial "demo() { echo one; }"
  assert_output --partial "# <<< devbot:demo <<<"
}

@test "upsert never creates a missing rc" {
  _devbot_shell_block_upsert "${BATS_TEST_TMPDIR}/absent" demo <<'EOF'
demo() { echo one; }
EOF

  [ ! -e "${BATS_TEST_TMPDIR}/absent" ]
}

@test "upsert replaces the previous block instead of duplicating it" {
  printf 'x=1\n' >"${RC}"
  _devbot_shell_block_upsert "${RC}" demo <<'EOF'
demo() { echo old; }
EOF
  _devbot_shell_block_upsert "${RC}" demo <<'EOF'
demo() { echo new; }
EOF

  run cat "${RC}"
  assert_output --partial "demo() { echo new; }"
  refute_output --partial "echo old"
  [ "$(grep -c '^# >>> devbot:demo >>>' "${RC}")" -eq 1 ]
}

@test "upsert is byte-identical on a second identical render" {
  printf 'x=1\n' >"${RC}"
  _devbot_shell_block_upsert "${RC}" demo <<'EOF'
demo() { echo one; }
EOF
  cp "${RC}" "${BATS_TEST_TMPDIR}/first"

  _devbot_shell_block_upsert "${RC}" demo <<'EOF'
demo() { echo one; }
EOF

  cmp -s "${BATS_TEST_TMPDIR}/first" "${RC}"
}

@test "upsert keeps the rest of the file, interior blank lines included" {
  printf 'one\n\ntwo\n\n\n' >"${RC}"
  cat >"${BATS_TEST_TMPDIR}/expected" <<'EOF'
one

two

# >>> devbot:demo >>>
demo() { :; }
# <<< devbot:demo <<<
EOF

  _devbot_shell_block_upsert "${RC}" demo <<'EOF'
demo() { :; }
EOF

  cmp -s "${BATS_TEST_TMPDIR}/expected" "${RC}"
}

@test "upsert leaves an unrelated devbot block alone" {
  printf 'x=1\n' >"${RC}"
  _devbot_shell_block_upsert "${RC}" other <<'EOF'
other() { :; }
EOF
  _devbot_shell_block_upsert "${RC}" demo <<'EOF'
demo() { :; }
EOF

  run cat "${RC}"
  assert_output --partial "# >>> devbot:other >>>"
  assert_output --partial "# >>> devbot:demo >>>"
}

# ── foreign function strip ───────────────────────────────────────────────────

@test "strip removes a name() definition and keeps the rest" {
  cat >"${RC}" <<'EOF'
export PATH="$HOME/bin:$PATH"
# how to run it
demo() {
  echo hi
}
alias ll='ls -l'
EOF

  _devbot_shell_function_strip "${RC}" demo

  run cat "${RC}"
  assert_output --partial 'export PATH="$HOME/bin:$PATH"'
  assert_output --partial "alias ll='ls -l'"
  refute_output --partial "demo() {"
  refute_output --partial "echo hi"
}

@test "strip removes a 'function name {' definition" {
  cat >"${RC}" <<'EOF'
x=1
function demo {
  echo hi
}
y=2
EOF

  _devbot_shell_function_strip "${RC}" demo

  run cat "${RC}"
  assert_line --index 0 "x=1"
  assert_line --index 1 "y=2"
}

@test "strip removes a one-line definition" {
  printf 'x=1\ndemo() { echo hi; }\ny=2\n' >"${RC}"

  _devbot_shell_function_strip "${RC}" demo

  run cat "${RC}"
  assert_output "x=1
y=2"
}

@test "strip drops the marker comment an older installer left above the function" {
  cat >"${RC}" <<'EOF'
x=1
# setup.sh:demo-wrapper
demo() {
  echo old
}
y=2
EOF

  _devbot_shell_function_strip "${RC}" demo

  run cat "${RC}"
  assert_line --index 0 "x=1"
  assert_line --index 1 "y=2"
  refute_output --partial "setup.sh:demo-wrapper"
}

@test "strip keeps a comment that does not name devbot or the function" {
  cat >"${RC}" <<'EOF'
# global settings
demo() {
  echo old
}
EOF

  _devbot_shell_function_strip "${RC}" demo

  run cat "${RC}"
  assert_output --partial "# global settings"
}

@test "strip leaves another function and a mention of the name alone" {
  cat >"${RC}" <<'EOF'
demo() { echo mine; }
other() {
  echo other
}
command demo --flag
EOF

  _devbot_shell_function_strip "${RC}" demo

  run cat "${RC}"
  assert_output --partial "other() {"
  assert_output --partial "echo other"
  assert_output --partial "command demo --flag"
  refute_output --partial "echo mine"
}

@test "strip is a no-op when the function is absent" {
  printf 'x=1\n' >"${RC}"
  cp "${RC}" "${BATS_TEST_TMPDIR}/first"

  _devbot_shell_function_strip "${RC}" demo

  cmp -s "${BATS_TEST_TMPDIR}/first" "${RC}"
}

# ── the pair, as a module uses it ───────────────────────────────────────────

@test "strip then upsert replaces a foreign definition with the managed block" {
  cat >"${RC}" <<'EOF'
x=1
# telamon:install.sh:demo-wrapper
demo() {
  echo hand-rolled
}
y=2
EOF

  _devbot_shell_function_strip "${RC}" demo
  _devbot_shell_block_upsert "${RC}" demo <<'EOF'
demo() {
  echo managed
}
EOF

  run cat "${RC}"
  assert_output --partial "echo managed"
  refute_output --partial "hand-rolled"
  refute_output --partial "telamon"
  [ "$(grep -c '^demo() {' "${RC}")" -eq 1 ]
}

@test "strip then upsert is idempotent when the block is already current" {
  printf 'x=1\n' >"${RC}"
  local body='demo() { echo managed; }'
  _devbot_shell_block_upsert "${RC}" demo <<<"${body}"
  cp "${RC}" "${BATS_TEST_TMPDIR}/first"

  _devbot_shell_function_strip "${RC}" demo
  _devbot_shell_block_upsert "${RC}" demo <<<"${body}"

  cmp -s "${BATS_TEST_TMPDIR}/first" "${RC}"
}

# ── the shapes a hand-rolled definition comes in ─────────────────────────────

@test "strip removes a definition whose closing brace carries a semicolon" {
  printf 'x=1\ndemo() { echo hi; };\ny=2\n' >"${RC}"

  _devbot_shell_function_strip "${RC}" demo

  run cat "${RC}"
  assert_output "x=1
y=2"
}

@test "strip removes a definition whose closing brace carries a comment" {
  printf 'x=1\ndemo() { echo hi; } # mine\ny=2\n' >"${RC}"

  _devbot_shell_function_strip "${RC}" demo

  run cat "${RC}"
  assert_output "x=1
y=2"
}

@test "strip removes a definition whose closing brace is indented" {
  printf 'x=1\ndemo() {\n  echo hi\n  }\ny=2\n' >"${RC}"

  _devbot_shell_function_strip "${RC}" demo

  run cat "${RC}"
  assert_output "x=1
y=2"
}

@test "strip keeps a body that holds a block of its own" {
  printf 'x=1\ndemo() {\n  if true; then\n    { echo in-block; }\n  fi\n}\ny=2\n' >"${RC}"

  _devbot_shell_function_strip "${RC}" demo

  run cat "${RC}"
  assert_output "x=1
y=2"
}

@test "strip leaves an unterminated definition alone and says so" {
  printf 'x=1\ndemo() {\n  echo hi\ny=2\n' >"${RC}"
  cp "${RC}" "${BATS_TEST_TMPDIR}/first"

  run _devbot_shell_function_strip "${RC}" demo

  assert_failure
  assert_output --partial "no matching closing brace"
  cmp -s "${BATS_TEST_TMPDIR}/first" "${RC}"
}

@test "strip counts braces through a quoted # without treating it as a comment" {
  # `#` inside quotes is data: cutting the line there would unbalance the brace
  # counter and report a definition that has a closing brace as unterminated.
  printf 'x=1\ndemo() { echo "a # b"; }\ny=2\n' >"${RC}"

  _devbot_shell_function_strip "${RC}" demo

  run cat "${RC}"
  assert_output "x=1
y=2"
}

@test "strip leaves a definition nested in a string alone" {
  printf 'x=1\nsketch() { echo "demo() { not a definition }"; }\ny=2\n' >"${RC}"

  _devbot_shell_function_strip "${RC}" demo

  run cat "${RC}"
  assert_output --partial 'sketch() { echo "demo() { not a definition }"; }'
}

# ── refusals that protect the user's file ───────────────────────────────────

@test "upsert refuses an empty render and keeps the previous block" {
  printf 'x=1\n' >"${RC}"
  _devbot_shell_block_upsert "${RC}" demo <<'EOF'
demo() { echo kept; }
EOF
  cp "${RC}" "${BATS_TEST_TMPDIR}/first"

  run _devbot_shell_block_upsert "${RC}" demo <<'EOF'

EOF

  assert_failure
  assert_output --partial "refusing to render an empty block"
  cmp -s "${BATS_TEST_TMPDIR}/first" "${RC}"
}

@test "upsert refuses a start marker without its end marker" {
  printf 'x=1\n# >>> devbot:demo >>>\ndemo() { echo old; }\n' >"${RC}"
  cp "${RC}" "${BATS_TEST_TMPDIR}/first"

  run _devbot_shell_block_upsert "${RC}" demo <<'EOF'
demo() { echo new; }
EOF

  assert_failure
  assert_output --partial "unpaired"
  cmp -s "${BATS_TEST_TMPDIR}/first" "${RC}"
}

@test "upsert refuses a body that would not parse and keeps the file" {
  # The rc is fine; the body is not. Nothing is written, and the message blames
  # the render rather than the user's file.
  printf 'x=1\n' >"${RC}"
  cp "${RC}" "${BATS_TEST_TMPDIR}/first"

  run _devbot_shell_block_upsert "${RC}" demo <<'EOF'
demo() { echo "unterminated
EOF

  assert_failure
  assert_output --partial "the rendered"
  assert_output --partial "would not parse"
  cmp -s "${BATS_TEST_TMPDIR}/first" "${RC}"
}

@test "upsert names a pre-existing syntax error instead of blaming the render" {
  # The file was already broken; the guard must not claim this edit broke it.
  printf 'if true; then\n' >"${RC}"
  cp "${RC}" "${BATS_TEST_TMPDIR}/first"

  run _devbot_shell_block_upsert "${RC}" demo <<'EOF'
demo() { echo new; }
EOF

  assert_failure
  assert_output --partial "did not parse before this edit"
  refute_output --partial "the rendered"
  cmp -s "${BATS_TEST_TMPDIR}/first" "${RC}"
}
