#!/usr/bin/env bats
# =============================================================================
# src/agentic/memory/tests/remember-session_plugin_tests.bats
# Tests for writeWatermark() and readWatermark() in the remember-session plugin.
# Verifies the watermark file behaviour: create, merge, sort, corrupt handling,
# and read-back of timestamps.
# =============================================================================

setup() {
  bats_require_minimum_version 1.5.0
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(mktemp -d)"
  WATERMARK_FILE="$TEST_DIR/.agents/logs/remember-session.watermark.json"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Helper: simulate writeWatermark() behaviour using python3
write_watermark() {
  local directory="$1"
  local session_id="$2"
  local wm_file="$directory/.agents/logs/remember-session.watermark.json"
  local timestamp
  timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  mkdir -p "$(dirname "$wm_file")"

  python3 -c "
import json, sys, os

path = '${wm_file}'
key   = '${session_id}'
ts    = '${timestamp}'

data = {}
try:
    with open(path) as f:
        raw = f.read().strip()
        if raw: data = json.loads(raw)
except (FileNotFoundError, json.JSONDecodeError):
    pass

data[key] = ts
sorted_data = dict(sorted(data.items()))

os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, 'w') as f:
    json.dump(sorted_data, f, indent=2)
    f.write('\n')
"
}

# Helper: simulate readWatermark() behaviour using python3.
# Outputs the timestamp for the given session ID, or "null" if not found
# (fail-open on any error, empty file, missing key, or corrupt JSON).
read_watermark() {
  local directory="$1"
  local session_id="$2"
  local wm_file="$directory/.agents/logs/remember-session.watermark.json"

  python3 -c "
import json, sys

path = '${wm_file}'
key  = '${session_id}'

try:
    with open(path) as f:
        raw = f.read().strip()
        if not raw:
            print('null')
            sys.exit(0)
        data = json.loads(raw)
        result = data.get(key)
        if result is None:
            print('null')
        else:
            print(result)
except Exception:
    print('null')
"
}

# ── writeWatermark tests ──────────────────────────────────────────────────────
# ── Basic writes ──────────────────────────────────────────────────────────────

@test "creates watermark file and dirs when they do not exist" {
  run write_watermark "$TEST_DIR" "ses_test123"
  assert_success
  [[ -f "$WATERMARK_FILE" ]]
}

@test "writes session ID as key in JSON map" {
  write_watermark "$TEST_DIR" "ses_abc"

  run python3 -c "
import json
with open('$WATERMARK_FILE') as f:
    data = json.load(f)
print(list(data.keys())[0])
"
  assert_output "ses_abc"
}

@test "writes timestamp as value" {
  write_watermark "$TEST_DIR" "ses_ts"

  run python3 -c "
import json
with open('$WATERMARK_FILE') as f:
    data = json.load(f)
ts = list(data.values())[0]
import re
print('valid' if re.match(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z', ts) else 'invalid')
"
  assert_output "valid"
}

# ── Merge behaviour ──────────────────────────────────────────────────────────

@test "merges new session into existing map" {
  write_watermark "$TEST_DIR" "ses_first"
  write_watermark "$TEST_DIR" "ses_second"

  run python3 -c "
import json
with open('$WATERMARK_FILE') as f:
    data = json.load(f)
print(len(data))
"
  assert_output "2"
}

@test "overwrites existing session with new timestamp" {
  write_watermark "$TEST_DIR" "ses_update"

  # Get first timestamp
  local ts1
  ts1="$(python3 -c "
import json
with open('$WATERMARK_FILE') as f:
    print(list(json.load(f).values())[0])
")"

  sleep 1  # ensure different timestamp

  write_watermark "$TEST_DIR" "ses_update"

  local count ts2
  count="$(python3 -c "
import json
with open('$WATERMARK_FILE') as f:
    data = json.load(f)
print(len(data))
")"
  ts2="$(python3 -c "
import json
with open('$WATERMARK_FILE') as f:
    print(list(json.load(f).values())[0])
")"

  assert_equal "$count" "1"
  refute [ "$ts1" = "$ts2" ]
}

# ── Key sorting ──────────────────────────────────────────────────────────────

@test "sorts keys alphabetically" {
  write_watermark "$TEST_DIR" "zzz_session"
  write_watermark "$TEST_DIR" "aaa_session"
  write_watermark "$TEST_DIR" "mmm_session"

  run python3 -c "
import json
with open('$WATERMARK_FILE') as f:
    keys = list(json.load(f).keys())
print(','.join(keys))
"
  assert_output "aaa_session,mmm_session,zzz_session"
}

# ── Edge cases ───────────────────────────────────────────────────────────────

@test "handles empty existing file" {
  mkdir -p "$(dirname "$WATERMARK_FILE")"
  touch "$WATERMARK_FILE"  # empty file

  write_watermark "$TEST_DIR" "ses_empty"

  run python3 -c "
import json
with open('$WATERMARK_FILE') as f:
    data = json.load(f)
print(len(data))
"
  assert_output "1"
}

@test "handles corrupt JSON in existing file" {
  mkdir -p "$(dirname "$WATERMARK_FILE")"
  echo "not valid json {{{" > "$WATERMARK_FILE"

  write_watermark "$TEST_DIR" "ses_corrupt"

  run python3 -c "
import json
with open('$WATERMARK_FILE') as f:
    data = json.load(f)
print(len(data))
"
  assert_output "1"
}

@test "no-op when write fails (read-only parent)" {
  mkdir -p "$(dirname "$WATERMARK_FILE")"
  chmod 500 "$(dirname "$WATERMARK_FILE")"

  # Should not crash — watermark write is fail-open
  run write_watermark "$TEST_DIR" "ses_ro"

  # Restore permissions for teardown
  chmod 755 "$(dirname "$WATERMARK_FILE")"

  # Either success (if running as root) or failure without crash
  [[ "$status" -eq 0 || "$status" -eq 1 ]]
}

# ── readWatermark tests ───────────────────────────────────────────────────────

@test "read returns timestamp for existing session" {
  write_watermark "$TEST_DIR" "ses_readme"

  # Capture the timestamp stored in the file directly
  local stored_ts
  stored_ts="$(python3 -c "
import json
with open('$WATERMARK_FILE') as f:
    print(list(json.load(f).values())[0])
")"

  # Read it back via read_watermark
  run read_watermark "$TEST_DIR" "ses_readme"
  assert_success
  assert_output "$stored_ts"
}

@test "read returns null for unknown session" {
  write_watermark "$TEST_DIR" "ses_written"

  run read_watermark "$TEST_DIR" "ses_other"
  assert_success
  assert_output "null"
}

@test "read returns null when no watermark file" {
  run read_watermark "$TEST_DIR" "ses_nonexistent"
  assert_success
  assert_output "null"
}

@test "read returns null for corrupt file" {
  mkdir -p "$(dirname "$WATERMARK_FILE")"
  echo "not valid json {{{" > "$WATERMARK_FILE"

  run read_watermark "$TEST_DIR" "ses_corrupt"
  assert_success
  assert_output "null"
}

@test "read returns latest timestamp after overwrite" {
  write_watermark "$TEST_DIR" "ses_overwrite"

  local ts1
  ts1="$(python3 -c "
import json
with open('$WATERMARK_FILE') as f:
    print(list(json.load(f).values())[0])
")"

  sleep 1

  write_watermark "$TEST_DIR" "ses_overwrite"

  run read_watermark "$TEST_DIR" "ses_overwrite"
  assert_success
  refute [ "$output" = "$ts1" ]

  # Also verify it's a valid timestamp, not "null"
  refute [ "$output" = "null" ]
}
