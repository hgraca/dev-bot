#!/usr/bin/env bats
# Tests for the agent-communication .ts tool (tools/agent-communication.ts)
# Tests the validateMessage function via the .sh CLI wrapper.

setup() {
  load "$(npm root -g)/bats-support/load.bash"
  load "$(npm root -g)/bats-assert/load.bash"

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  TOOL_DIR="$MODULE_DIR/tools"
  FIXTURES="$TEST_DIR/fixtures"
  mkdir -p "$FIXTURES"
}

teardown() {
  find "$FIXTURES" -maxdepth 1 -name 'tmp.*' -exec rm -f {} + 2>/dev/null || true
}

# ── Helpers ──────────────────────────────────────────────────────────────────

write_fixture() {
  local name="$1"
  local content="$2"
  local path="$FIXTURES/$name"
  printf '%s' "$content" > "$path"
  printf '%s' "$path"
}

# ── Tool file exists ─────────────────────────────────────────────────────────

@test "tool agent-communication: shell wrapper exists and is executable" {
  [ -f "$TOOL_DIR/agent-communication.sh" ]
  [ -x "$TOOL_DIR/agent-communication.sh" ]
}

@test "tool agent-communication: mcp-meta reports valid metadata" {
  run bash "$TOOL_DIR/agent-communication.sh" mcp-meta
  assert_success
  run python3 -c "import json,sys; json.loads(sys.stdin.read()); print('VALID')" <<< "$output"
  assert_output "VALID"
}

# ── validateMessage: [FINISHED] marker ──────────────────────────────────────────

@test "tool agent-communication: detects [FINISHED] marker" {
  local tmpfile
  tmpfile="$(mktemp "$FIXTURES/tmp.XXXXXX.json")"

  python3 -c "
import json
msg = {'info': {'role': 'assistant'}, 'parts': [{'type': 'text', 'text': 'All work is complete.\n\n[FINISHED]'}]}
with open('$tmpfile', 'w') as f:
    json.dump(msg, f)
"

  run bash "$TOOL_DIR/agent-communication.sh" --msg-file "$tmpfile"
  assert_success
  [[ "$output" == *"OK — terminal marker found"* ]] || fail "expected OK (got: ${output:0:300})"

  rm -f "$tmpfile"
}

@test "tool agent-communication: detects [BLOCKED] marker" {
  local tmpfile
  tmpfile="$(mktemp "$FIXTURES/tmp.XXXXXX.json")"

  python3 -c "
import json
msg = {'info': {'role': 'assistant'}, 'parts': [{'type': 'text', 'text': 'Cannot proceed.\n\n[BLOCKED] CI pipeline is failing'}]}
with open('$tmpfile', 'w') as f:
    json.dump(msg, f)
"

  run bash "$TOOL_DIR/agent-communication.sh" --msg-file "$tmpfile"
  assert_success
  [[ "$output" == *"OK — terminal marker found"* ]] || fail "expected OK (got: ${output:0:300})"

  rm -f "$tmpfile"
}

@test "tool agent-communication: detects [NEEDS_INPUT] marker" {
  local tmpfile
  tmpfile="$(mktemp "$FIXTURES/tmp.XXXXXX.json")"

  python3 -c "
import json
msg = {'info': {'role': 'assistant'}, 'parts': [{'type': 'text', 'text': 'Two approaches.\n\n[NEEDS_INPUT] Should we use Redis?'}]}
with open('$tmpfile', 'w') as f:
    json.dump(msg, f)
"

  run bash "$TOOL_DIR/agent-communication.sh" --msg-file "$tmpfile"
  assert_success
  [[ "$output" == *"OK — terminal marker found"* ]] || fail "expected OK (got: ${output:0:300})"

  rm -f "$tmpfile"
}

@test "tool agent-communication: detects [PARTIAL] marker" {
  local tmpfile
  tmpfile="$(mktemp "$FIXTURES/tmp.XXXXXX.json")"

  python3 -c "
import json
msg = {'info': {'role': 'assistant'}, 'parts': [{'type': 'text', 'text': 'Domain model done.\n\n[PARTIAL] Controller still needed'}]}
with open('$tmpfile', 'w') as f:
    json.dump(msg, f)
"

  run bash "$TOOL_DIR/agent-communication.sh" --msg-file "$tmpfile"
  assert_success
  [[ "$output" == *"OK — terminal marker found"* ]] || fail "expected OK (got: ${output:0:300})"

  rm -f "$tmpfile"
}

# ── validateMessage: missing marker ───────────────────────────────────────────

@test "tool agent-communication: flags missing terminal marker" {
  local tmpfile
  tmpfile="$(mktemp "$FIXTURES/tmp.XXXXXX.json")"

  python3 -c "
import json
msg = {'info': {'role': 'assistant'}, 'parts': [{'type': 'text', 'text': 'Just some work in progress'}]}
with open('$tmpfile', 'w') as f:
    json.dump(msg, f)
"

  run bash "$TOOL_DIR/agent-communication.sh" --msg-file "$tmpfile"
  assert_failure
  [[ "$output" == *"Missing terminal marker"* ]] || fail "expected 'Missing terminal marker' (got: ${output:0:300})"

  rm -f "$tmpfile"
}

@test "tool agent-communication: empty message passes (no content to check)" {
  local tmpfile
  tmpfile="$(mktemp "$FIXTURES/tmp.XXXXXX.json")"

  python3 -c "
import json
msg = {'info': {'role': 'assistant'}, 'parts': [{'type': 'text', 'text': ''}]}
with open('$tmpfile', 'w') as f:
    json.dump(msg, f)
"

  run bash "$TOOL_DIR/agent-communication.sh" --msg-file "$tmpfile"
  assert_success
  [[ "$output" == *"OK — terminal marker found"* ]] || fail "expected OK for empty message (got: ${output:0:300})"

  rm -f "$tmpfile"
}

# ── validateMessage: fenced code block ───────────────────────────────────────

@test "tool agent-communication: detects marker after fenced code block" {
  local tmpfile
  tmpfile="$(mktemp "$FIXTURES/tmp.XXXXXX.json")"

  python3 -c "
import json
msg = {'info': {'role': 'assistant'}, 'parts': [{'type': 'text', 'text': 'Here is the implementation:\n\n\`\`\`typescript\nfunction add(a: number, b: number): number {\n  return a + b;\n}\n\`\`\`\n\n[FINISHED]'}]}
with open('$tmpfile', 'w') as f:
    json.dump(msg, f)
"

  run bash "$TOOL_DIR/agent-communication.sh" --msg-file "$tmpfile"
  assert_success
  [[ "$output" == *"OK — terminal marker found"* ]] || fail "expected OK after fenced block (got: ${output:0:300})"

  rm -f "$tmpfile"
}

# ── validateMessage: error cases ──────────────────────────────────────────────

@test "tool agent-communication: fails on non-existent file" {
  run bash "$TOOL_DIR/agent-communication.sh" --msg-file "/nonexistent/path.json"
  assert_failure
  [[ "$output" == *"Message file not found"* ]] || fail "expected 'not found' (got: ${output:0:300})"
}

@test "tool agent-communication: fails when --msg-file missing" {
  run bash "$TOOL_DIR/agent-communication.sh"
  assert_failure
  [[ "$output" == *"msg-file"* ]] || fail "expected msg-file error (got: ${output:0:300})"
}

@test "tool agent-communication: fails on invalid JSON" {
  local tmpfile
  tmpfile="$(mktemp "$FIXTURES/tmp.XXXXXX.json")"
  echo "not valid json" > "$tmpfile"

  run bash "$TOOL_DIR/agent-communication.sh" --msg-file "$tmpfile"
  assert_failure
  [[ "$output" == *"Invalid JSON"* ]] || fail "expected 'Invalid JSON' (got: ${output:0:300})"

  rm -f "$tmpfile"
}

# ── validateMessage: user messages are always valid ───────────────────────────

@test "tool agent-communication: user messages always pass (no marker check)" {
  local tmpfile
  tmpfile="$(mktemp "$FIXTURES/tmp.XXXXXX.json")"

  python3 -c "
import json
msg = {'info': {'role': 'user'}, 'parts': [{'type': 'text', 'text': 'Can you help me with the login?'}]}
with open('$tmpfile', 'w') as f:
    json.dump(msg, f)
"

  run bash "$TOOL_DIR/agent-communication.sh" --msg-file "$tmpfile"
  assert_success
  [[ "$output" == *"OK — terminal marker found"* ]] || fail "expected OK for user message (got: ${output:0:300})"

  rm -f "$tmpfile"
}

# ── validateMessage: multi-part messages ──────────────────────────────────────

@test "tool agent-communication: handles multi-part messages" {
  local tmpfile
  tmpfile="$(mktemp "$FIXTURES/tmp.XXXXXX.json")"

  python3 -c "
import json
msg = {'info': {'role': 'assistant'}, 'parts': [
    {'type': 'text', 'text': 'First part of the response.'},
    {'type': 'text', 'text': 'Second part.\n\n[FINISHED]'}
]}
with open('$tmpfile', 'w') as f:
    json.dump(msg, f)
"

  run bash "$TOOL_DIR/agent-communication.sh" --msg-file "$tmpfile"
  assert_success
  [[ "$output" == *"OK — terminal marker found"* ]] || fail "expected OK for multi-part (got: ${output:0:300})"

  rm -f "$tmpfile"
}

@test "tool agent-communication: handles multi-part missing marker" {
  local tmpfile
  tmpfile="$(mktemp "$FIXTURES/tmp.XXXXXX.json")"

  python3 -c "
import json
msg = {'info': {'role': 'assistant'}, 'parts': [
    {'type': 'text', 'text': 'First part.'},
    {'type': 'text', 'text': 'Second part without marker'}
]}
with open('$tmpfile', 'w') as f:
    json.dump(msg, f)
"

  run bash "$TOOL_DIR/agent-communication.sh" --msg-file "$tmpfile"
  assert_failure
  [[ "$output" == *"Missing terminal marker"* ]] || fail "expected 'Missing terminal marker' (got: ${output:0:300})"

  rm -f "$tmpfile"
}
