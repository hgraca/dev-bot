#!/usr/bin/env bats
# =============================================================================
# src/harnesses/opencode/tests/intelephense_lsp_tests.bats
# Tests for the Intelephense LSP launch wrapper and its version pin.
#
# opencode's built-in PHP server resolves the intelephense binary itself. The
# config override that delivers intelephense.files.exclude must re-declare the
# launch command, and intelephense is not on PATH — so this wrapper prefers the
# copy devbot pins, falls back to opencode's, and caps the heap via NODE_OPTIONS.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  WRAPPER="$MODULE_DIR/lsp/intelephense.sh"
  BASH_BIN="$(command -v bash)"
}

# Write a stub intelephense at the node_modules/.bin dir passed as $1.
_stub_intelephense() {
  mkdir -p "$1"
  printf '#!/bin/sh\necho INTELEPHENSE "$*" NODE_OPTIONS="$NODE_OPTIONS"\n' > "$1/intelephense"
  chmod +x "$1/intelephense"
}

# ── wrapper ───────────────────────────────────────────────────────────────────

@test "wrapper: exists, is executable, and parses (bash -n)" {
  [[ -f "${WRAPPER}" ]]
  [[ -x "${WRAPPER}" ]]
  run bash -n "${WRAPPER}"
  assert_success
}

@test "wrapper: prefers the copy devbot pins under the devbot root" {
  local root
  root="$(mktemp -d)"
  _stub_intelephense "${root}/storage/intelephense/node_modules/.bin"

  run env DEV_BOT_ROOT="${root}" HOME="${root}/home" PATH="/usr/bin:/bin" "${BASH_BIN}" "${WRAPPER}" --stdio

  assert_success
  assert_output --partial "INTELEPHENSE --stdio"
  rm -rf "${root}"
}

@test "wrapper: falls back to opencode's copy under XDG_DATA_HOME" {
  local root
  root="$(mktemp -d)"
  _stub_intelephense "${root}/data/opencode/bin/node_modules/.bin"

  run env DEV_BOT_ROOT="${root}/devbot" HOME="${root}/home" XDG_DATA_HOME="${root}/data" \
    PATH="/usr/bin:/bin" "${BASH_BIN}" "${WRAPPER}" --stdio

  assert_success
  assert_output --partial "INTELEPHENSE --stdio"
  rm -rf "${root}"
}

@test "wrapper: caps the server heap via NODE_OPTIONS" {
  local root
  root="$(mktemp -d)"
  _stub_intelephense "${root}/storage/intelephense/node_modules/.bin"

  run env DEV_BOT_ROOT="${root}" HOME="${root}/home" PATH="/usr/bin:/bin" "${BASH_BIN}" "${WRAPPER}"

  assert_success
  assert_output --partial "--max-old-space-size=2048"
  rm -rf "${root}"
}

@test "wrapper: FATALs when intelephense cannot be found" {
  local root
  root="$(mktemp -d)"
  mkdir -p "${root}/emptybin"

  run env DEV_BOT_ROOT="${root}/devbot" HOME="${root}/home" XDG_DATA_HOME="${root}/data" \
    XDG_CACHE_HOME="${root}/cache" PATH="${root}/emptybin" "${BASH_BIN}" "${WRAPPER}"

  assert_failure
  assert_output --partial "FATAL:"
  rm -rf "${root}"
}

# ── version pin ───────────────────────────────────────────────────────────────

@test "versions.env: pins a semver intelephense version" {
  [[ -f "${MODULE_DIR}/versions.env" ]]
  run bash -c "source '${MODULE_DIR}/versions.env' && [[ -n \"\${INTELEPHENSE_VERSION:-}\" ]]"
  assert_success
  run grep -cE '^INTELEPHENSE_VERSION=[0-9]+\.[0-9]+\.[0-9]+$' "${MODULE_DIR}/versions.env"
  assert_equal "$output" "1"
}

@test "install.sh: exists, is executable, installs the pin into storage/intelephense" {
  [[ -x "${MODULE_DIR}/install.sh" ]]
  run grep -qF 'npm install --silent --prefix "${PREFIX}" "intelephense@${INTELEPHENSE_VERSION}"' "${MODULE_DIR}/install.sh"
  assert_success
  run grep -q 'storage/intelephense' "${MODULE_DIR}/install.sh"
  assert_success
}

@test "install.sh: resolves the devbot root and runs (stubbed npm)" {
  local stub
  stub="$(mktemp -d)"
  printf '#!/bin/sh\nexit 0\n' > "${stub}/npm"
  chmod +x "${stub}/npm"

  run env PATH="${stub}:${PATH}" bash "${MODULE_DIR}/install.sh"

  assert_success
  rm -r "${stub}"
}

@test "update.sh: delegates to install.sh and never bumps the pin" {
  [[ -x "${MODULE_DIR}/update.sh" ]]
  run grep -q 'install\.sh' "${MODULE_DIR}/update.sh"
  assert_success
  # no auto-bump: the pin is bumped by a deliberate commit, never by this script
  refute grep -q 'npm view' "${MODULE_DIR}/update.sh"
}

@test "update.sh: provisions the pin without rewriting versions.env" {
  local stub before after
  stub="$(mktemp -d)"
  printf '#!/bin/sh\nexit 0\n' > "${stub}/npm"
  chmod +x "${stub}/npm"
  before="$(cat "${MODULE_DIR}/versions.env")"

  run env PATH="${stub}:${PATH}" bash "${MODULE_DIR}/update.sh"

  assert_success
  after="$(cat "${MODULE_DIR}/versions.env")"
  [ "${before}" = "${after}" ]
  rm -r "${stub}"
}
