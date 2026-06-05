#!/usr/bin/env bats
# Tests for the reindex-memories.sh bash entrypoint.

setup() {
  load "$(npm root -g)/bats-support/load.bash"
  load "$(npm root -g)/bats-assert/load.bash"

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  TOOL="$MODULE_DIR/tools/reindex-memories/reindex-memories.sh"

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
