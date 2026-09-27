#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/upsert_opencode_permission_tests.bats
# Tests for upsert_opencode_permission.py — adds a "<path>/**": "allow" entry to
# the permission.external_directory map in opencode.jsonc.
#
# audit-65 FAIL-1: the old close-finder matched the first line that was exactly
# "}" or "},". When the block was glued (`…"allow"},`), it walked into the
# *following* "bash" block's close; because the grant was already present in
# "bash", the upsert reported "already present" and silently skipped — leaving
# the install dir unreadable through external_directory.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"
  TOOL="${PROJECT_ROOT}/src/_shared/upsert_opencode_permission.py"

  WORK="$(mktemp -d)"
}

teardown() {
  rm -rf "$WORK" 2>/dev/null || true
}

@test "upsert: inserts the grant into a well-formed external_directory block" {
  cat > "$WORK/opencode.jsonc" <<'JSONC_EOF'
{
  "permission": {
    "external_directory": {
      "*": "deny",
      "/tmp/**": "allow"
    }
  }
}
JSONC_EOF
  run python3 "$TOOL" "$WORK/opencode.jsonc" "/a/dev-bot/**"

  assert_success
  assert_output --partial "added to external_directory"
  run python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['permission']['external_directory']['/a/dev-bot/**'])" "$WORK/opencode.jsonc"
  assert_output "allow"
}

@test "upsert: glued block + same key already in the bash block still gets the grant" {
  # The exact shape audit-65 hit: external_directory's close is glued to its last
  # entry, and "/x/dev-bot/**" is already present in the *bash* block. The old
  # line-shape finder walked into bash and no-op'd.
  cat > "$WORK/opencode.jsonc" <<'JSONC_EOF'
{
  "permission": {
    "external_directory": {    "*": "deny",
    "/tmp/**": "allow",
    "/x/.config/opencode/**": "allow"},
    "bash": {
      "*": "allow",
      "/x/dev-bot/**": "allow"
    }
  }
}
JSONC_EOF
  run python3 "$TOOL" "$WORK/opencode.jsonc" "/x/dev-bot/**"

  assert_success
  assert_output --partial "added to external_directory"
  # The grant must now live inside external_directory (not only bash), and the
  # file must still be valid JSON.
  run python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert d['permission']['external_directory']['/x/dev-bot/**']=='allow', 'grant missing from external_directory'; print('ok')" "$WORK/opencode.jsonc"
  assert_output "ok"
}

@test "upsert: a brace inside a comment does not end the block early" {
  cat > "$WORK/opencode.jsonc" <<'JSONC_EOF'
{
  "permission": {
    "external_directory": {
      "*": "deny",
      // a stray } in a line comment
      "/tmp/**": "allow"
    },
    "bash": {
      "/x/dev-bot/**": "allow"
    }
  }
}
JSONC_EOF
  run python3 "$TOOL" "$WORK/opencode.jsonc" "/x/dev-bot/**"

  assert_success
  assert_output --partial "added to external_directory"
  # The grant must land inside external_directory (before the bash block), not
  # spliced into the comment; the comment itself is preserved.
  run python3 -c "s=open('$WORK/opencode.jsonc').read(); assert '/x/dev-bot/**' in s.split('\"bash\"')[0], 'grant landed in the wrong block'; assert 'a stray } in a line comment' in s; print('ok')"
  assert_output "ok"
}

@test "upsert: is idempotent (second run reports already present)" {
  cat > "$WORK/opencode.jsonc" <<'JSONC_EOF'
{
  "permission": {
    "external_directory": {
      "*": "deny",
      "/tmp/**": "allow"
    }
  }
}
JSONC_EOF
  run python3 "$TOOL" "$WORK/opencode.jsonc" "/a/dev-bot/**"
  assert_output --partial "added to external_directory"

  run python3 "$TOOL" "$WORK/opencode.jsonc" "/a/dev-bot/**"
  assert_success
  assert_output --partial "already present"
}

@test "upsert: no external_directory block → skip with exit 0" {
  printf '{\n  "permission": { "edit": "allow" }\n}\n' > "$WORK/opencode.jsonc"
  run python3 "$TOOL" "$WORK/opencode.jsonc" "/a/dev-bot/**"
  assert_success
  assert_output --partial "no permission.external_directory block"
}
