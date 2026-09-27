#!/usr/bin/env bats
# =============================================================================
# src/agentic/forensics/tests/forensics_tests.bats
# Tests for the forensics module — lifecycle skeleton (T0.1) and the plugin
# registry contract (T0.2). Later phases append analysis tests here.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  TOOL="${MODULE_DIR}/tools/forensics.sh"
  LIB="${MODULE_DIR}/lib/forensics-lib.py"
  LANGS="${MODULE_DIR}/langs"
  EDGE_LANGS="${TEST_DIR}/fixtures/langs-edge"
}

# ── Skeleton (T0.1) ────────────────────────────────────────────────────────────

@test "functions.sh: sources cleanly and exposes shared helpers" {
  run bash -c "source '${MODULE_DIR}/functions.sh' && declare -F _info >/dev/null && declare -F _warn >/dev/null"
  assert_success
}

@test "pre.sh: exits 0" {
  run bash "${MODULE_DIR}/pre.sh"
  assert_success
}

@test "install.sh: is idempotent (second run succeeds)" {
  run bash "${MODULE_DIR}/install.sh"
  assert_success

  run bash "${MODULE_DIR}/install.sh"
  assert_success
}

# ── CLI surface ────────────────────────────────────────────────────────────────

# The tool is a plain CLI, like refactor: the `devbot:forensics` skill documents
# it and an agent runs `devbot tool forensics <command>`. It is NOT an MCP tool.

@test "not an MCP tool: no .mcp.sh wrapper" {
  run bash -c "ls '${MODULE_DIR}'/tools/*.mcp.sh 2>/dev/null"
  assert_failure
}

@test "--version: prints the tool version and exits 0" {
  run bash "${TOOL}" --version
  assert_success
  assert_output --regexp "^forensics [0-9]+\.[0-9]+\.[0-9]+$"
}

@test "--help: prints usage and exits 0" {
  run bash "${TOOL}" --help
  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "mine"
}

@test "no command: prints usage to stderr and exits non-zero" {
  run bash "${TOOL}"
  assert_failure
  assert_output --partial "Usage:"
}

@test "unknown command: fails with an ERROR" {
  run bash "${TOOL}" bogus-command
  assert_failure
  assert_output --partial "ERROR"
}

# ── Plugin registry (T0.2) ─────────────────────────────────────────────────────

@test "langs --format json: emits valid JSON listing the php plugin" {
  run bash "${TOOL}" langs --format json
  assert_success
  echo "${output}" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
assert doc["ok"] is True, doc
langs = [p["lang"] for p in doc["plugins"]]
assert "php" in langs, langs
assert doc["errors"] == [], doc["errors"]
'
}

@test "langs: default markdown output names the php plugin" {
  run bash "${TOOL}" langs
  assert_success
  assert_output --partial "php"
}

@test "langs: a malformed plugin is rejected with an ERROR and non-zero exit" {
  run env FORENSICS_LANGS_DIR="${EDGE_LANGS}" bash "${TOOL}" langs --format json
  assert_failure
  assert_output --partial "ERROR"
}

@test "langs: a plugin missing a required meta key is reported as an error" {
  run env FORENSICS_LANGS_DIR="${TEST_DIR}/fixtures/langs-nokey" bash "${TOOL}" langs --format json
  assert_failure
  assert_output --partial "ERROR"
}
