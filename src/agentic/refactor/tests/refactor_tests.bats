#!/usr/bin/env bats
# =============================================================================
# src/agentic/refactor/tests/refactor_tests.bats
# Tests for the refactor module: lifecycle skeleton (T1) and, as it lands, the
# tool contract (mcp-meta, plugin registry, PHP plan/apply, safety gates).
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  TOOL="${MODULE_DIR}/tools/refactor/refactor.mcp.sh"
  FIXTURE_LANGS="${TEST_DIR}/fixtures/langs"
}

# ── Skeleton ───────────────────────────────────────────────────────────────────

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

# ── Tool contract: mcp-meta + CLI surface (T2) ─────────────────────────────────

@test "mcp-meta: emits valid JSON with name=refactor" {
  run bash "${TOOL}" mcp-meta
  assert_success

  local name
  name="$(printf '%s' "${output}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["name"])')"
  [ "${name}" = "refactor" ]
}

@test "mcp-meta: declares a single required args array" {
  run bash "${TOOL}" mcp-meta
  assert_success

  local ok
  ok="$(printf '%s' "${output}" | python3 -c 'import json,sys; p=json.load(sys.stdin)["parameters"]; print("yes" if p["properties"]["args"]["type"]=="array" and p.get("required")==["args"] else "no")')"
  [ "${ok}" = "yes" ]
}

@test "--version: prints the tool version and exits 0" {
  command -v bun >/dev/null 2>&1 || skip "bun not installed"

  run bash "${TOOL}" --version
  assert_success
  assert_output --regexp "^refactor [0-9]+\.[0-9]+\.[0-9]+$"
}

@test "--help: prints usage and exits 0" {
  command -v bun >/dev/null 2>&1 || skip "bun not installed"

  run bash "${TOOL}" --help
  assert_success
  assert_output --partial "Usage:"
}

@test "no args: reports an ERROR and exits non-zero" {
  command -v bun >/dev/null 2>&1 || skip "bun not installed"

  run bash "${TOOL}"
  assert_failure
  assert_output --partial "ERROR:"
}

# ── Plugin seam: registry + dispatch (T3) ──────────────────────────────────────
#
# The stublang fixture is a language the core has never heard of, discovered
# purely because it sits under REFACTOR_LANGS_DIR. These tests are the
# additivity proof: a new language needs no edit to refactor.ts.

@test "plugin seam: dispatches to a language discovered from REFACTOR_LANGS_DIR" {
  command -v bun >/dev/null 2>&1 || skip "bun not installed"
  export REFACTOR_LANGS_DIR="${FIXTURE_LANGS}"

  run bash "${TOOL}" --lang stublang --op rename-method \
    --class 'App\Foo' --method old --to new

  assert_success
  assert_output --partial "## refactor: rename-method"
  assert_output --partial "**Engine:** stub 1.0.0"
  assert_output --partial "old -> new"
}

@test "plugin seam: forwards --apply to the plugin" {
  command -v bun >/dev/null 2>&1 || skip "bun not installed"
  export REFACTOR_LANGS_DIR="${FIXTURE_LANGS}"

  run bash "${TOOL}" --lang stublang --op rename-method \
    --class 'App\Foo' --method old --to new --apply --json

  assert_success
  assert_output --partial '"applied": true'
}

@test "plugin seam: the request contract survives the hop" {
  command -v bun >/dev/null 2>&1 || skip "bun not installed"
  export REFACTOR_LANGS_DIR="${FIXTURE_LANGS}"

  run bash "${TOOL}" --lang stublang --op rename-method \
    --class 'App\Foo' --method old --to new --json

  assert_success
  assert_output --partial '"op": "rename-method"'
  assert_output --partial '"from": "old"'
  assert_output --partial '"to": "new"'
}

@test "plugin seam: unknown language lists what is available" {
  command -v bun >/dev/null 2>&1 || skip "bun not installed"
  export REFACTOR_LANGS_DIR="${FIXTURE_LANGS}"

  run bash "${TOOL}" --lang nope --op rename-method --class X --method a --to b

  assert_failure
  assert_output --partial "unknown language 'nope'"
  assert_output --partial "available: stublang"
}

@test "plugin seam: an op the plugin does not declare is rejected" {
  command -v bun >/dev/null 2>&1 || skip "bun not installed"
  export REFACTOR_LANGS_DIR="${FIXTURE_LANGS}"

  run bash "${TOOL}" --lang stublang --op rename-class --class X --to b

  assert_failure
  assert_output --partial "does not support op 'rename-class'"
}

@test "plugin seam: an empty langs dir yields no available languages" {
  command -v bun >/dev/null 2>&1 || skip "bun not installed"

  local empty
  empty="$(mktemp -d)"
  export REFACTOR_LANGS_DIR="${empty}"

  run bash "${TOOL}" --lang php --op rename-method --class X --method a --to b
  rm -r "${empty}"

  assert_failure
  assert_output --partial "unknown language 'php'"
  assert_output --partial "available: none"
}
