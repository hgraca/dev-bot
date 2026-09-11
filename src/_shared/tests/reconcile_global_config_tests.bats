#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/reconcile_global_config_tests.bats
# Tests for reconcile_global_config.py — aligns the runtime global config
# (.devbot.global.jsonc) with the shipped schema (.devbot.global.dist.jsonc).
#
# Contract: top-level properties (keys) only.
#   - add each dist key absent from the runtime file (copying dist's value and
#     its trailing // comment)
#   - remove each runtime key absent from the dist file
#   - leave keys present in both byte-for-byte (runtime value + comment win)
#   - nested objects are OPAQUE — never reconciled
#   - text surgery: comments/layout of untouched properties are preserved
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"
  TOOL="${PROJECT_ROOT}/src/_shared/reconcile_global_config.py"
  READER="${PROJECT_ROOT}/src/_shared/read_jsonc.py"

  WORK="$(mktemp -d)"
}

teardown() {
  rm -rf "$WORK" 2>/dev/null || true
}

# Parse the runtime config and print a top-level key's JSON value.
_read_key() {
  python3 "$READER" "$WORK/runtime.jsonc" "$1"
}

@test "adds a dist-only key, copying its value and trailing comment" {
  cat > "$WORK/dist.jsonc" <<'JSONC_EOF'
{
  "a": 1,
  "new_key": "hello" // migrated in 1.5.0
}
JSONC_EOF
  cat > "$WORK/runtime.jsonc" <<'JSONC_EOF'
{
  "a": 1
}
JSONC_EOF

  run python3 "$TOOL" "$WORK/dist.jsonc" "$WORK/runtime.jsonc"
  assert_success
  grep -qF 'ADDED: new_key' <<< "$output" || fail "ADDED not reported"

  assert_equal "$(_read_key new_key)" "hello"
  grep -qF '// migrated in 1.5.0' "$WORK/runtime.jsonc"
}

@test "removes a runtime-only key" {
  cat > "$WORK/dist.jsonc" <<'JSONC_EOF'
{
  "a": 1
}
JSONC_EOF
  cat > "$WORK/runtime.jsonc" <<'JSONC_EOF'
{
  "a": 1,
  "retired": true
}
JSONC_EOF

  run python3 "$TOOL" "$WORK/dist.jsonc" "$WORK/runtime.jsonc"
  assert_success
  grep -qF 'REMOVED: retired' <<< "$output" || fail "REMOVED not reported"

  run python3 -c "
import sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
d = load_jsonc('${WORK}/runtime.jsonc')
assert 'retired' not in d, d
assert d['a'] == 1, d
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "shared keys keep their runtime value and comment (dist value ignored)" {
  cat > "$WORK/dist.jsonc" <<'JSONC_EOF'
{
  "auto_update": true, // dist default
  "shared": { "a": 1 } // dist shared
}
JSONC_EOF
  cat > "$WORK/runtime.jsonc" <<'JSONC_EOF'
{
  "auto_update": false, // machine choice
  "shared": { "a": 2 } // runtime shared
}
JSONC_EOF

  local before
  before="$(cat "$WORK/runtime.jsonc")"

  run python3 "$TOOL" "$WORK/dist.jsonc" "$WORK/runtime.jsonc"
  assert_success
  grep -qF 'NOCHANGE' <<< "$output" || fail "expected no-op"

  # Byte-for-byte unchanged.
  assert_equal "$(cat "$WORK/runtime.jsonc")" "$before"
  assert_equal "$(_read_key auto_update)" "false"
  grep -qF '// machine choice' "$WORK/runtime.jsonc"
  refute grep -qF '// dist default' "$WORK/runtime.jsonc"
}

@test "nested objects are opaque — a differing modules map is not reconciled" {
  cat > "$WORK/dist.jsonc" <<'JSONC_EOF'
{
  "modules": { "react": false }
}
JSONC_EOF
  cat > "$WORK/runtime.jsonc" <<'JSONC_EOF'
{
  "modules": { "svelte": false }
}
JSONC_EOF

  run python3 "$TOOL" "$WORK/dist.jsonc" "$WORK/runtime.jsonc"
  assert_success

  run python3 -c "
import sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
d = load_jsonc('${WORK}/runtime.jsonc')
assert d['modules'] == {'svelte': False}, d
print('OPAQUE')
"
  assert_success
  assert_output "OPAQUE"
}

@test "removing the last property leaves no dangling comma" {
  cat > "$WORK/dist.jsonc" <<'JSONC_EOF'
{
  "keep": 1
}
JSONC_EOF
  cat > "$WORK/runtime.jsonc" <<'JSONC_EOF'
{
  "keep": 1,
  "drop": 2
}
JSONC_EOF

  run python3 "$TOOL" "$WORK/dist.jsonc" "$WORK/runtime.jsonc"
  assert_success

  run python3 -c "
import sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
d = load_jsonc('${WORK}/runtime.jsonc')
assert d == {'keep': 1}, d
print('VALID')
"
  assert_success
  assert_output "VALID"
}

@test "adding into an empty runtime object yields a valid object" {
  printf '{\n}\n' > "$WORK/runtime.jsonc"
  cat > "$WORK/dist.jsonc" <<'JSONC_EOF'
{
  "only": "x"
}
JSONC_EOF

  run python3 "$TOOL" "$WORK/dist.jsonc" "$WORK/runtime.jsonc"
  assert_success

  assert_equal "$(_read_key only)" "x"
}

@test "is idempotent — a second run is a byte-identical no-op" {
  cat > "$WORK/dist.jsonc" <<'JSONC_EOF'
{
  "a": 1,
  "new_key": "hello" // comment
}
JSONC_EOF
  cat > "$WORK/runtime.jsonc" <<'JSONC_EOF'
{
  "a": 1,
  "old": true
}
JSONC_EOF

  run python3 "$TOOL" "$WORK/dist.jsonc" "$WORK/runtime.jsonc"
  assert_success
  local after_first
  after_first="$(cat "$WORK/runtime.jsonc")"

  run python3 "$TOOL" "$WORK/dist.jsonc" "$WORK/runtime.jsonc"
  assert_success
  grep -qF 'NOCHANGE' <<< "$output" || fail "second run should be a no-op"
  assert_equal "$(cat "$WORK/runtime.jsonc")" "$after_first"
}

@test "missing runtime file is a no-op (exit 0)" {
  cat > "$WORK/dist.jsonc" <<'JSONC_EOF'
{
  "a": 1
}
JSONC_EOF

  run python3 "$TOOL" "$WORK/dist.jsonc" "$WORK/nope.jsonc"
  assert_success
  [ ! -e "$WORK/nope.jsonc" ]
}

@test "missing dist file is an error (exit 1)" {
  printf '{\n  "a": 1\n}\n' > "$WORK/runtime.jsonc"
  local before
  before="$(cat "$WORK/runtime.jsonc")"

  run python3 "$TOOL" "$WORK/nope.jsonc" "$WORK/runtime.jsonc"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR"* ]]
  assert_equal "$(cat "$WORK/runtime.jsonc")" "$before"
}

@test "unparseable dist leaves the runtime untouched (exit 1)" {
  printf '{\n  "a": \n' > "$WORK/dist.jsonc"
  printf '{\n  "a": 1\n}\n' > "$WORK/runtime.jsonc"
  local before
  before="$(cat "$WORK/runtime.jsonc")"

  run python3 "$TOOL" "$WORK/dist.jsonc" "$WORK/runtime.jsonc"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR"* ]]
  assert_equal "$(cat "$WORK/runtime.jsonc")" "$before"
}

# ── Comma/comment interaction (review findings 1-3) ─────────────────────────
# The separator comma belongs before a trailing `// comment`, never after it.
# A second comma emitted after a comment is swallowed by the comment, and a
# comma appended after a comment produces invalid JSONC.

@test "adds multiple keys, keeping the separator comma before a comment" {
  cat > "$WORK/dist.jsonc" <<'JSONC_EOF'
{
  "a": 1,
  "k1": "v1", // first
  "k2": "v2" // second
}
JSONC_EOF
  cat > "$WORK/runtime.jsonc" <<'JSONC_EOF'
{
  "a": 1
}
JSONC_EOF

  run python3 "$TOOL" "$WORK/dist.jsonc" "$WORK/runtime.jsonc"
  assert_success

  run python3 -c "
import sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
d = load_jsonc('${WORK}/runtime.jsonc')
assert d == {'a': 1, 'k1': 'v1', 'k2': 'v2'}, d
print('MULTI')
"
  assert_success
  assert_output "MULTI"
  grep -qF '"k1": "v1", // first' "$WORK/runtime.jsonc"
}

@test "adding a key after an annotated last property keeps the comment attached" {
  cat > "$WORK/dist.jsonc" <<'JSONC_EOF'
{
  "a": 1,
  "b": 2
}
JSONC_EOF
  cat > "$WORK/runtime.jsonc" <<'JSONC_EOF'
{
  "a": 1 // keep me
}
JSONC_EOF

  run python3 "$TOOL" "$WORK/dist.jsonc" "$WORK/runtime.jsonc"
  assert_success

  run python3 -c "
import sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
d = load_jsonc('${WORK}/runtime.jsonc')
assert d == {'a': 1, 'b': 2}, d
print('OK')
"
  assert_success
  assert_output "OK"
  grep -qF '"a": 1, // keep me' "$WORK/runtime.jsonc"
}

@test "removing a property after an annotated one leaves no dangling comma" {
  cat > "$WORK/dist.jsonc" <<'JSONC_EOF'
{
  "keep": 1
}
JSONC_EOF
  cat > "$WORK/runtime.jsonc" <<'JSONC_EOF'
{
  "keep": 1, // keep me
  "drop": 2
}
JSONC_EOF

  run python3 "$TOOL" "$WORK/dist.jsonc" "$WORK/runtime.jsonc"
  assert_success

  run python3 -c "
import sys
sys.path.insert(0, '${PROJECT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
d = load_jsonc('${WORK}/runtime.jsonc')
assert d == {'keep': 1}, d
print('OK')
"
  assert_success
  assert_output "OK"
  grep -qF '// keep me' "$WORK/runtime.jsonc"
}

@test "unparseable runtime leaves the file untouched (exit 1)" {
  printf '{\n  "a": 1\n}\n' > "$WORK/dist.jsonc"
  printf '{\n  "a": \n' > "$WORK/runtime.jsonc"
  local before
  before="$(cat "$WORK/runtime.jsonc")"

  run python3 "$TOOL" "$WORK/dist.jsonc" "$WORK/runtime.jsonc"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR"* ]]
  assert_equal "$(cat "$WORK/runtime.jsonc")" "$before"
}

@test "wrong argument count prints usage and exits 1" {
  run python3 "$TOOL" "$WORK/only-one.jsonc"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "an unreadable runtime is an error, not a silent no-op (exit 1)" {
  printf '{\n  "a": 1\n}\n' > "$WORK/dist.jsonc"
  mkdir -p "$WORK/runtime-as-dir.jsonc"

  run python3 "$TOOL" "$WORK/dist.jsonc" "$WORK/runtime-as-dir.jsonc"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR"* ]]
}

@test "a successful reconcile leaves no temp file behind" {
  cat > "$WORK/dist.jsonc" <<'JSONC_EOF'
{
  "a": 1,
  "b": 2
}
JSONC_EOF
  printf '{\n  "a": 0\n}\n' > "$WORK/runtime.jsonc"

  run python3 "$TOOL" "$WORK/dist.jsonc" "$WORK/runtime.jsonc"
  assert_success
  [ ! -e "$WORK/runtime.jsonc.reconcile.tmp" ]
}


