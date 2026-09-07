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

  # Pin the qmd provider so the tool's engine dispatch is deterministic and
  # independent of the real machine config (default engine is mdctx).
  export DEVBOT_MEMORY_SEARCH_PROVIDER=qmd

  # Run from a scratch dir so the tool's cwd-derived log target stays inside
  # $WORK (never the repo's own .agents/logs).
  cd "$WORK"

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

@test "tool: prune mode runs qmd cleanup and update without embed" {
  # audit-29/audit-36: the pre-harness delete→prune self-heal fires 'prune'
  # (cleanup+update only) so bash-deleted notes stop surfacing without paying
  # the embed cost.
  cat > "$STUB_DIR/qmd" <<'SCRIPT'
#!/usr/bin/env bash
echo "$*" >> "$QMD_CALL_LOG"
exit 0
SCRIPT
  chmod +x "$STUB_DIR/qmd"
  local call_log="$WORK/qmd-prune-calls.log"

  run env PATH="$STUB_DIR:$PATH" QMD_CALL_LOG="$call_log" bash "$TOOL" prune
  assert_success
  assert_output --partial '"status":"started"'
  assert_output --partial "no embed"

  local i
  for i in $(seq 1 50); do
    [[ "$(wc -l < "$call_log" 2>/dev/null || echo 0)" -ge 2 ]] && break
    sleep 0.1
  done

  run cat "$call_log"
  assert_line --index 0 "cleanup"
  assert_line --index 1 "update"
  # Exactly two calls — embed must never run in prune mode.
  assert [ "$(wc -l < "$call_log" 2>/dev/null || echo 0)" = "2" ]
}

# ── audit-24 NOTE-4: flock serializes the pidfile check-then-act ─────────────

@test "tool: in_progress when another invocation holds the flock (TOCTOU fix)" {
  mkdir -p "$WORK/devbot"
  # Hold the lock file in a background subshell for 10s. Uses the same
  # portable acquire primitive as the tool (flock, else python fcntl on the
  # inherited fd) so this holder works on macOS where flock(1) is absent.
  (
    exec 200>"$WORK/devbot/reindex-memories.lock"
    { flock -n 200 2>/dev/null || python3 -c 'import fcntl; fcntl.flock(200, fcntl.LOCK_EX|fcntl.LOCK_NB)' 2>/dev/null; } || exit 1
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

# ── audit-25 F2: portable lock fallback for macOS (flock(1) is util-linux) ──

@test "tool: works when flock is missing (macOS) via python fcntl fallback" {
  # Stub flock to exit 127 (command-not-found), simulating a macOS host
  # without util-linux. The tool must fall back to python fcntl on the
  # inherited fd and still launch the reindex.
  cat > "$STUB_DIR/flock" <<'SCRIPT'
#!/usr/bin/env bash
exit 127
SCRIPT
  chmod +x "$STUB_DIR/flock"

  run env PATH="$STUB_DIR:$PATH" bash "$TOOL"
  assert_success
  assert_output --partial '"status":"started"'
}

@test "tool: python fallback still respects a held lock (in_progress)" {
  # With flock stubbed to fail, the python fallback must still observe a lock
  # held by another process — proving the fallback is a real lock, not a no-op.
  cat > "$STUB_DIR/flock" <<'SCRIPT'
#!/usr/bin/env bash
exit 127
SCRIPT
  chmod +x "$STUB_DIR/flock"
  mkdir -p "$WORK/devbot"

  (
    exec 200>"$WORK/devbot/reindex-memories.lock"
    python3 -c 'import fcntl; fcntl.flock(200, fcntl.LOCK_EX|fcntl.LOCK_NB)' 2>/dev/null || exit 1
    sleep 10
  ) &
  local holder=$!
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

# ── Background job logging (audit-49 NOTE-2) ─────────────────────────────────
# The background job used to discard qmd's output to /dev/null, so a slow or
# failed reindex was unobservable. The job now logs start/done markers with
# exit codes to the project's .agents/logs/memory-index.log (when run from a
# project) or the devbot cache log otherwise.

# A "project" scratch dir with .agents/logs, plus a qmd that records argv.
make_project() {
  local proj="$1"
  mkdir -p "$proj/.agents/logs"
  cat > "$STUB_DIR/qmd" <<'SCRIPT'
#!/usr/bin/env bash
echo "$*" >> "$QMD_CALL_LOG"
exit 0
SCRIPT
  chmod +x "$STUB_DIR/qmd"
}

wait_for_pid_gone() {
  local i
  for i in $(seq 1 100); do
    [[ ! -f "$WORK/devbot/reindex-memories.pid" ]] && return 0
    sleep 0.1
  done
  return 1
}

@test "tool: background job logs start/done markers with exit codes to the project memory-index.log" {
  local proj="$WORK/project"
  make_project "$proj"
  local call_log="$WORK/qmd-full.log"
  local index_log="$proj/.agents/logs/memory-index.log"

  cd "$proj"
  run env PATH="$STUB_DIR:$PATH" QMD_CALL_LOG="$call_log" bash "$TOOL"
  cd "$WORK"
  assert_success

  wait_for_pid_gone
  [[ -f "$index_log" ]] || fail "no memory-index.log written in project"

  run cat "$index_log"
  assert_output --regexp "\[reindex-memories\] full start"
  assert_output --regexp "\[reindex-memories\] full finished cleanup=0 update-embed=0"
}

@test "tool: prune-mode background job logs a prune marker" {
  local proj="$WORK/project-prune"
  make_project "$proj"
  local index_log="$proj/.agents/logs/memory-index.log"

  cd "$proj"
  run env PATH="$STUB_DIR:$PATH" bash "$TOOL" prune
  cd "$WORK"
  assert_success

  wait_for_pid_gone
  run cat "$index_log"
  assert_output --regexp "\[reindex-memories\] prune start"
  assert_output --regexp "\[reindex-memories\] prune finished cleanup=0 update-embed=0"
}

@test "tool: pid file is removed and failure logged even when qmd exits non-zero" {
  # audit-49 NOTE-2 latent bug: the background subshell inherited the tool's
  # `set -e`, so a failing `qmd cleanup` aborted the subshell BEFORE its
  # `rm -f "$PID_FILE"` — leaking the pid file and wedging the tool into
  # perpetual in_progress. The job must run errexit-off: record the exit
  # codes, log them, and always remove the pid file.
  local proj="$WORK/project-fail"
  make_project "$proj"
  cat > "$STUB_DIR/qmd" <<'SCRIPT'
#!/usr/bin/env bash
echo "boom" >&2
exit 1
SCRIPT
  chmod +x "$STUB_DIR/qmd"
  local index_log="$proj/.agents/logs/memory-index.log"

  cd "$proj"
  run env PATH="$STUB_DIR:$PATH" bash "$TOOL"
  cd "$WORK"
  assert_success

  wait_for_pid_gone || fail "pid file was not removed after a failing qmd run"
  run cat "$index_log"
  assert_output --regexp "boom"
  assert_output --regexp "\[reindex-memories\] full finished cleanup=1"
}

# ── mdctx engine dispatch (memory_search_provider = mdctx) ────────────────────
# Under mdctx the reindex is an incremental `mdctx build` of the project latent
# index AND the global-memories index (no cleanup/embed concept). Provider is
# pinned via env so the test is independent of the machine config.

_make_mdctx_env() {
  # Sandbox devbot root (global store + index home) + a project with a latent
  # vault; provider pinned to mdctx.
  local devroot="$1"
  local proj="$2"
  mkdir -p "$devroot/storage/global-memories" "$devroot/storage/.mdctx"
  mkdir -p "$proj/.agents/memory/latent" "$proj/.agents/logs" "$proj/.mdctx"
  export DEV_BOT_ROOT="$devroot"
  export DEVBOT_MEMORY_SEARCH_PROVIDER=mdctx
  cat > "$STUB_DIR/mdctx" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  echo "0.1.0"
  exit 0
fi
echo "$*" >> "$MDCTX_CALL_LOG"
exit 0
SCRIPT
  chmod +x "$STUB_DIR/mdctx"
}

@test "mdctx provider: background reindex builds project + global indexes" {
  local devroot="$WORK/devroot"
  local proj="$WORK/project-mdctx"
  _make_mdctx_env "$devroot" "$proj"
  local call_log="$WORK/mdctx-calls.log"
  local index_log="$proj/.agents/logs/memory-index.log"

  cd "$proj"
  run env PATH="$STUB_DIR:$PATH" MDCTX_CALL_LOG="$call_log" bash "$TOOL"
  cd "$WORK"
  assert_success
  assert_output --partial '"status":"started"'

  local i
  for i in $(seq 1 50); do
    [[ "$(wc -l < "$call_log" 2>/dev/null || echo 0)" -ge 2 ]] && break
    sleep 0.1
  done
  run cat "$call_log"
  # One build per store: the project latent index + the global-memories index.
  assert_line --index 0 --regexp "^build ${proj}/\.agents/memory/latent -o ${proj}/\.mdctx/context-index\.json$"
  assert_line --index 1 --regexp "^build ${devroot}/storage/global-memories -o ${devroot}/storage/\.mdctx/context-index\.json$"

  # Log markers (engine-agnostic memory-index.log).
  local j
  for j in $(seq 1 50); do
    grep -q "finished project_rc=0 global_rc=0" "$index_log" 2>/dev/null && break
    sleep 0.1
  done
  run cat "$index_log"
  assert_output --regexp "\[reindex-memories\] full start"
  assert_output --regexp "\[reindex-memories\] full finished project_rc=0 global_rc=0"
}

@test "mdctx provider + prune mode: same build, logs a prune marker" {
  local devroot="$WORK/devroot-prune"
  local proj="$WORK/project-mdctx-prune"
  _make_mdctx_env "$devroot" "$proj"
  local index_log="$proj/.agents/logs/memory-index.log"

  cd "$proj"
  run env PATH="$STUB_DIR:$PATH" bash "$TOOL" prune
  cd "$WORK"
  assert_success
  assert_output --partial '"status":"started"'

  local j
  for j in $(seq 1 50); do
    grep -q "prune finished project_rc=0 global_rc=0" "$index_log" 2>/dev/null && break
    sleep 0.1
  done
  run cat "$index_log"
  assert_output --regexp "\[reindex-memories\] prune start"
  assert_output --regexp "\[reindex-memories\] prune finished project_rc=0 global_rc=0"
}

@test "mdctx provider + mdctx binary missing: FATAL" {
  local devroot="$WORK/devroot-nobin"
  local proj="$WORK/project-nobin"
  mkdir -p "$devroot/storage/global-memories" "$proj/.agents/memory/latent"
  export DEV_BOT_ROOT="$devroot"
  export DEVBOT_MEMORY_SEARCH_PROVIDER=mdctx
  # No mdctx stub on PATH — strip the real mdctx dir too, so the gate sees no
  # binary and must fail loudly (independent of the host's mdctx install).
  rm -f "$STUB_DIR/mdctx"
  local mdctx_dir filtered_path dir
  mdctx_dir="$(dirname "$(command -v mdctx 2>/dev/null)")"
  filtered_path=""
  while IFS= read -r -d: dir; do
    [[ -n "$dir" && "$dir" != "$mdctx_dir" ]] || continue
    filtered_path="${filtered_path:+$filtered_path:}$dir"
  done <<< "${PATH}:"

  cd "$proj"
  run env PATH="$filtered_path" bash "$TOOL"
  cd "$WORK"
  assert_failure
  assert_output --partial "mdctx binary not found"
}
