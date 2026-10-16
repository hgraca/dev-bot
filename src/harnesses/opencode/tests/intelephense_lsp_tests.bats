#!/usr/bin/env bats
# =============================================================================
# src/harnesses/opencode/tests/intelephense_lsp_tests.bats
# Tests for the Intelephense LSP launch wrapper.
#
# opencode's built-in PHP server resolves the intelephense binary itself. A
# config override (used to deliver intelephense.files.exclude through LSP
# workspace/configuration) must re-declare the launch command, and intelephense
# is not on PATH — so this wrapper resolves the copy opencode installed under
# its global bin dir.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  WRAPPER="$MODULE_DIR/lsp/intelephense.sh"
  BASH_BIN="$(command -v bash)"
}

@test "wrapper: exists, is executable, and parses (bash -n)" {
  [[ -f "${WRAPPER}" ]]
  [[ -x "${WRAPPER}" ]]
  run bash -n "${WRAPPER}"
  assert_success
}

@test "wrapper: execs the intelephense binary opencode installed" {
  local home
  home="$(mktemp -d)"
  local bin="${home}/.local/share/opencode/bin/node_modules/.bin"
  mkdir -p "${bin}"
  printf '#!/bin/sh\necho INTELEPHENSE-CALLED "$*"\n' > "${bin}/intelephense"
  chmod +x "${bin}/intelephense"

  run env HOME="${home}" PATH="/usr/bin:/bin" "${BASH_BIN}" "${WRAPPER}" --stdio

  assert_success
  assert_output --partial "INTELEPHENSE-CALLED --stdio"
  rm -rf "${home}"
}

@test "wrapper: FATALs when intelephense cannot be found" {
  local home
  home="$(mktemp -d)"
  mkdir -p "${home}/emptybin"

  run env HOME="${home}" PATH="${home}/emptybin" "${BASH_BIN}" "${WRAPPER}"

  assert_failure
  assert_output --partial "FATAL:"
  rm -rf "${home}"
}
