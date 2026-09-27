#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/reconcile_external_directory_tests.bats
# Tests for reconcile_external_directory.py — rebuilds the
# permission.external_directory map in opencode.jsonc (deny-first, /tmp/**,
# opencode log + config allowed).
#
# audit-65 FAIL-1: the inline version this replaced joined the entries with
# ",\n" but emitted no leading/trailing newline, so the rebuilt block read
# `"external_directory": {    "*": "deny",` … `"allow"},` — braces glued to the
# first/last entry. That defeat the companion upsert's close-finder. These tests
# pin the well-formed output and the glued-input normalisation.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"
  TOOL="${PROJECT_ROOT}/src/_shared/reconcile_external_directory.py"

  WORK="$(mktemp -d)"
  export HOME="/home/fake"
}

teardown() {
  rm -rf "$WORK" 2>/dev/null || true
}

_write_config() {
  cat > "$WORK/opencode.jsonc" <<'JSONC_EOF'
{
  "permission": {
    "external_directory": {
      "*": "deny",
      "/tmp/**": "allow"
    },
    "edit": "allow"
  }
}
JSONC_EOF
}

@test "reconcile: adds the log+config allows and emits a well-formed block" {
  _write_config
  run env HOME=/home/fake python3 "$TOOL" "$WORK/opencode.jsonc"

  assert_success
  assert_output "1"

  cat > "$WORK/expected" <<'JSONC_EOF'
{
  "permission": {
    "external_directory": {
      "*": "deny",
      "/tmp/**": "allow",
      "/home/fake/.local/share/opencode/log/**": "allow",
      "/home/fake/.config/opencode/**": "allow"
    },
    "edit": "allow"
  }
}
JSONC_EOF
  run diff "$WORK/expected" "$WORK/opencode.jsonc"
  assert_success
}

@test "reconcile: is idempotent (second run is a no-op)" {
  _write_config
  run env HOME=/home/fake python3 "$TOOL" "$WORK/opencode.jsonc"
  assert_output "1"
  local sha_before sha_after
  sha_before="$(sha256sum "$WORK/opencode.jsonc" | awk '{print $1}')"

  run env HOME=/home/fake python3 "$TOOL" "$WORK/opencode.jsonc"
  assert_success
  assert_output "0"
  sha_after="$(sha256sum "$WORK/opencode.jsonc" | awk '{print $1}')"
  assert_equal "$sha_before" "$sha_after"
}

@test "reconcile: no block → prints 0 and leaves the file untouched" {
  printf '{\n  "permission": { "edit": "allow" }\n}\n' > "$WORK/opencode.jsonc"
  local sha_before sha_after
  sha_before="$(sha256sum "$WORK/opencode.jsonc" | awk '{print $1}')"

  run env HOME=/home/fake python3 "$TOOL" "$WORK/opencode.jsonc"
  assert_success
  assert_output "0"
  sha_after="$(sha256sum "$WORK/opencode.jsonc" | awk '{print $1}')"
  assert_equal "$sha_before" "$sha_after"
}

@test "reconcile: normalises a glued block (audit-65 FAIL-1 regression)" {
  # The exact shape the old inline rebuild produced.
  cat > "$WORK/opencode.jsonc" <<'JSONC_EOF'
{
  "permission": {
    "external_directory": {    "*": "deny",
    "/tmp/**": "allow",
    "/home/fake/.config/opencode/**": "allow"},
    "edit": "allow"
  }
}
JSONC_EOF
  run env HOME=/home/fake python3 "$TOOL" "$WORK/opencode.jsonc"
  assert_success
  assert_output "1"

  # The opening brace must no longer share a line with the first entry.
  refute grep -q '"external_directory": {[[:space:]]*"' "$WORK/opencode.jsonc"
  # And the block must carry the log allow it was missing.
  run grep -q '"/home/fake/.local/share/opencode/log/\*\*": "allow"' "$WORK/opencode.jsonc"
  assert_success
}

@test "reconcile: normalises a complete-but-glued block (does not skip it)" {
  # All required allows present, but the braces are glued: the reconciler must
  # still rewrite it into the canonical multi-line form rather than short-circuit.
  cat > "$WORK/opencode.jsonc" <<'JSONC_EOF'
{
  "permission": {
    "external_directory": {    "*": "deny",
    "/tmp/**": "allow",
    "/home/fake/.local/share/opencode/log/**": "allow",
    "/home/fake/.config/opencode/**": "allow"},
    "edit": "allow"
  }
}
JSONC_EOF
  run env HOME=/home/fake python3 "$TOOL" "$WORK/opencode.jsonc"
  assert_success
  assert_output "1"
  refute grep -q '"external_directory": {[[:space:]]*"' "$WORK/opencode.jsonc"
}

@test "reconcile: migrates the legacy single-level /tmp glob" {
  printf '{\n  "permission": {\n    "external_directory": {\n      "*": "deny",\n      "/tmp/*": "allow"\n    }\n  }\n}\n' \
    > "$WORK/opencode.jsonc"
  run env HOME=/home/fake python3 "$TOOL" "$WORK/opencode.jsonc"
  assert_success
  run grep -q '"/tmp/\*\*": "allow"' "$WORK/opencode.jsonc"
  assert_success
}
