#!/usr/bin/env bats
# =============================================================================
# src/harnesses/opencode/tests/lsp_reconcile_tests.bats
# Tests that reset.sh reconciles the shipped lsp override into an existing
# opencode.jsonc — the dist block is seed-once, so an install seeded before it
# existed would otherwise keep `"lsp": true` forever.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  ROOT="$(cd "$MODULE_DIR/../../.." && pwd)"
  RESET="$MODULE_DIR/reset.sh"
  READER="$ROOT/src/_shared/read_jsonc.py"
}

@test "reset.sh: seeds the lsp override into an existing opencode.jsonc" {
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "${tmp}/.opencode"
  printf '{\n  "lsp": true,\n  "model": "x"\n}\n' > "${tmp}/opencode.jsonc"

  run bash "${RESET}" "${tmp}"

  assert_success
  run python3 "${READER}" "${tmp}/opencode.jsonc" lsp
  assert_output --partial '"php intelephense"'
  assert_output --partial '**/vendor/**/tests/**'
  # other keys are preserved
  run python3 "${READER}" "${tmp}/opencode.jsonc" model
  assert_output "x"
  rm -r "${tmp}"
}

@test "reset.sh: adds the worktree exclusion to an existing lsp override" {
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "${tmp}/.opencode"
  printf '{\n  "lsp": {\n    "php intelephense": {\n      "command": ["bash", "x", "--stdio"],\n      "initialization": { "intelephense": { "files": { "exclude": ["**/.git/**"] } } }\n    }\n  }\n}\n' > "${tmp}/opencode.jsonc"

  run bash "${RESET}" "${tmp}"

  assert_success
  run python3 "${READER}" "${tmp}/opencode.jsonc" lsp
  assert_output --partial '**/.agents/worktrees/**'
  assert_output --partial '**/.git/**'
  rm -r "${tmp}"
}

@test "reset.sh: leaves a user's own lsp object untouched" {
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "${tmp}/.opencode"
  printf '{\n  "lsp": { "custom": { "disabled": true } }\n}\n' > "${tmp}/opencode.jsonc"

  run bash "${RESET}" "${tmp}"

  assert_success
  run python3 "${READER}" "${tmp}/opencode.jsonc" lsp
  assert_output --partial '"custom"'
  refute_output --partial '"php intelephense"'
  rm -r "${tmp}"
}
