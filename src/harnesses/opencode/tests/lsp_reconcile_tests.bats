#!/usr/bin/env bats
# =============================================================================
# src/harnesses/opencode/tests/lsp_reconcile_tests.bats
# Tests that reset.sh reconciles the shipped lsp override into an existing
# opencode.jsonc — the dist block is seed-once, so an install seeded before it
# existed would otherwise keep `"lsp": true` forever.
#
# The fixture pins the harness through DEV_BOT_GLOBAL_CONFIG rather than a
# project `harness` key: the selection is global, so a project key loses to a
# machine running opencode-v2 and reset.sh then skips the project entirely.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  ROOT="$(cd "$MODULE_DIR/../../.." && pwd)"
  RESET="$MODULE_DIR/reset.sh"
  READER="$ROOT/src/_shared/read_jsonc.py"
  tmp=""

  GLOBAL_CONFIG="$(mktemp "${TMPDIR:-/tmp}/devbot-global.XXXXXX")"
  printf '{ "harness": "opencode" }\n' >"${GLOBAL_CONFIG}"
  export DEV_BOT_GLOBAL_CONFIG="${GLOBAL_CONFIG}"
}

teardown() {
  [[ -n "${tmp}" ]] && rm -r "${tmp}"
  rm -f "${GLOBAL_CONFIG:-}"
  unset DEV_BOT_GLOBAL_CONFIG
}

# A project fixture carrying $1 as its opencode.jsonc.
_make_project() {
  tmp="$(mktemp -d)"
  mkdir -p "${tmp}/.opencode"
  printf '%s' "$1" >"${tmp}/opencode.jsonc"
}

# reset.sh's skip message proves nothing under test ran; assert it is absent.
_assert_harness_selected() {
  refute_output --partial 'is not the selected harness'
}

@test "reset.sh: seeds the lsp override into an existing opencode.jsonc" {
  _make_project '{
  "lsp": true,
  "model": "x"
}
'

  run bash "${RESET}" "${tmp}"

  assert_success
  _assert_harness_selected
  run python3 "${READER}" "${tmp}/opencode.jsonc" lsp
  assert_output --partial '"php intelephense"'
  assert_output --partial '**/vendor/**/tests/**'
  # other keys are preserved
  run python3 "${READER}" "${tmp}/opencode.jsonc" model
  assert_output "x"
}

@test "reset.sh: adds the worktree exclusion to an existing lsp override" {
  _make_project '{
  "lsp": {
    "php intelephense": {
      "command": ["bash", "x", "--stdio"],
      "initialization": { "intelephense": { "files": { "exclude": ["**/.git/**"] } } }
    }
  }
}
'

  run bash "${RESET}" "${tmp}"

  assert_success
  _assert_harness_selected
  run python3 "${READER}" "${tmp}/opencode.jsonc" lsp
  assert_output --partial '**/.agents/worktrees/**'
  assert_output --partial '**/.git/**'
}

@test "reset.sh: leaves a user's own lsp object untouched" {
  _make_project '{
  "lsp": { "custom": { "disabled": true } }
}
'

  run bash "${RESET}" "${tmp}"

  assert_success
  _assert_harness_selected
  run python3 "${READER}" "${tmp}/opencode.jsonc" lsp
  assert_output --partial '"custom"'
  refute_output --partial '"php intelephense"'
}
