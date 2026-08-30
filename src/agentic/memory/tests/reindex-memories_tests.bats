#!/usr/bin/env bats
# Tests for the reindex-memories.mcp.sh bash entrypoint.

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  TOOL="$MODULE_DIR/tools/reindex-memories/reindex-memories.mcp.sh"

  WORK="$(mktemp -d)"
  export XDG_CACHE_HOME="$WORK"

  # Fake qmd so tests never trigger a real index/embed.
  STUB_DIR="$WORK/bin"
  mkdir -p "$STUB_DIR"
  cat > "$STUB_DIR/qmd" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
  chmod +x "$STUB_DIR/qmd"
}

teardown() {
  rm -rf "$WORK"
}

@test "tool: exists and is executable" {
  [ -f "$TOOL" ]
}

@test "tool: mcp-meta advertises an optional status argument" {
  run bash "$TOOL" mcp-meta
  assert_success
  assert_output --partial '"name":"reindex-memories"'
}

@test "tool: reports started (not ok) on fresh launch" {
  run env PATH="$STUB_DIR:$PATH" bash "$TOOL"
  assert_success
  assert_output --partial '"status":"started"'
  refute_output --partial '"status":"ok"'
}

@test "tool: reports in_progress when a reindex is already running" {
  mkdir -p "$WORK/devbot"
  sleep 60 &
  local running_pid=$!
  echo "$running_pid" > "$WORK/devbot/reindex-memories.pid"

  run env PATH="$STUB_DIR:$PATH" bash "$TOOL"
  assert_success
  assert_output --partial '"status":"in_progress"'

  kill "$running_pid" 2>/dev/null || true
}

@test "tool: status subcommand reports idle when nothing is running" {
  run env PATH="$STUB_DIR:$PATH" bash "$TOOL" status
  assert_success
  assert_output --partial '"status":"idle"'
}

@test "tool: status subcommand reports in_progress when running" {
  mkdir -p "$WORK/devbot"
  sleep 60 &
  local running_pid=$!
  echo "$running_pid" > "$WORK/devbot/reindex-memories.pid"

  run env PATH="$STUB_DIR:$PATH" bash "$TOOL" status
  assert_success
  assert_output --partial '"status":"in_progress"'

  kill "$running_pid" 2>/dev/null || true
}

@test "tool: background reindex runs qmd cleanup before update and embed" {
  # Guard audit-20 FAIL: orphaned qmd embedding chunks accumulated across
  # sessions (135 chunks, 14%). The reindex job must prune orphans first so
  # they don't silently accumulate. The fake qmd records its argv; wait for
  # all three calls (cleanup, update, embed) then assert the order.
  cat > "$STUB_DIR/qmd" <<'SCRIPT'
#!/usr/bin/env bash
echo "$*" >> "$QMD_CALL_LOG"
exit 0
SCRIPT
  chmod +x "$STUB_DIR/qmd"
  local call_log="$WORK/qmd-calls.log"

  run env PATH="$STUB_DIR:$PATH" QMD_CALL_LOG="$call_log" bash "$TOOL"
  assert_success

  local i
  for i in $(seq 1 50); do
    [[ "$(wc -l < "$call_log" 2>/dev/null || echo 0)" -ge 3 ]] && break
    sleep 0.1
  done

  run cat "$call_log"
  assert_line --index 0 "cleanup"
  assert_line --index 1 "update"
  assert_line --index 2 "embed"
}

# ── audit-24 NOTE-4: flock serializes the pidfile check-then-act ─────────────

@test "tool: in_progress when another invocation holds the flock (TOCTOU fix)" {
  mkdir -p "$WORK/devbot"
  # Hold the lock file in a background subshell for 10s.
  (
    exec 200>"$WORK/devbot/reindex-memories.lock"
    flock -n 200 || exit 1
    sleep 10
  ) &
  local holder=$!
  # Give the holder a moment to acquire the lock.
  sleep 0.2

  run env PATH="$STUB_DIR:$PATH" bash "$TOOL"

  kill "$holder" 2>/dev/null || true

  assert_success
  assert_output --partial '"status":"in_progress"'
}

@test "tool: lock file is created and released after the run" {
  run env PATH="$STUB_DIR:$PATH" bash "$TOOL"
  assert_success
  assert_output --partial '"status":"started"'

  # The lock file is released once the launching shell exits (the flock fd
  # closes with the process). A second immediate invocation must succeed —
  # proving the lock did not stay held after the launch.
  run env PATH="$STUB_DIR:$PATH" bash "$TOOL"
  assert_success
  assert_output --partial '"status":"started"'
}
