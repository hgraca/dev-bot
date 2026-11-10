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
state="${XDG_CACHE_HOME}/qmd-collection-path"
case "${1:-} ${2:-}" in
  "collection show")
    path="$(cat "$state" 2>/dev/null || true)"
    [[ -n "$path" ]] || exit 1
    printf 'Path: %s\n' "$path"
    ;;
  "collection add") printf '%s\n' "${3:-}" > "$state" ;;
  "collection remove") : > "$state" ;;
esac
SCRIPT
  chmod +x "$STUB_DIR/qmd"
}

teardown() {
  rm -rf "$WORK"
}

_make_qmd_migration_stub() {
  cat > "$STUB_DIR/qmd" <<'SCRIPT'
#!/usr/bin/env bash
echo "$*" >> "$QMD_ALL_CALLS"
case "${1:-} ${2:-}" in
  "collection show")
    if [[ "${QMD_SHOW_FAIL:-0}" == "1" ]]; then
      exit 1
    fi
    if [[ "${QMD_OMIT_PATH:-0}" == "1" ]]; then
      echo "Collection exists"
      exit 0
    fi
    path="$(cat "${QMD_STATE:?}/${3:-}" 2>/dev/null || true)"
    [[ -n "$path" ]] || exit 1
    printf 'Path: %s\n' "$path"
    ;;
  "collection remove")
    rm -f "${QMD_STATE:?}/${3:-}"
    ;;
  "collection add")
    shift 2
    path=""; name=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --name) name="$2"; shift 2 ;;
        *) [[ -z "$path" ]] && path="$1"; shift ;;
      esac
    done
    if [[ "${QMD_SHOW_FAIL:-0}" == "1" && -n "$(ls -A "${QMD_STATE:?}" 2>/dev/null)" ]]; then
      exit 1
    fi
    if [[ "${path}" == "${QMD_TARGET}" && "${QMD_FAIL_TARGET_ADD:-0}" == "1" ]]; then
      exit 1
    fi
    printf '%s\n' "$path" > "${QMD_STATE:?}/${name}"
    ;;
  "cleanup "| "update ")
    echo "$1" >> "$QMD_CALL_LOG"
    if [[ "$1" == "update" && "${QMD_UPDATE_FAIL:-0}" == "1" ]]; then
      exit 1
    fi
    ;;
esac
SCRIPT
  chmod +x "$STUB_DIR/qmd"
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

@test "tool: background reindex runs qmd cleanup then update (no embed)" {
  # Guard audit-20 FAIL: stale qmd chunks accumulated across sessions. The
  # reindex job must prune first so they don't silently accumulate. BM25-only:
  # exactly two calls (cleanup, update) — never embed (ADR
  # 20260913072905-qmd-bm25-only-no-model-downloads).
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
    [[ "$(wc -l < "$call_log" 2>/dev/null || echo 0)" -ge 2 ]] && break
    sleep 0.1
  done

  run cat "$call_log"
  assert_line "cleanup"
  assert_line "update"
  # Registration calls may precede them; embed must never run.
  refute_line --regexp '^embed'
}

@test "tool: prune mode runs the same qmd cleanup + update (no embed)" {
  # audit-29/audit-36: the pre-harness delete→prune self-heal fires 'prune' so
  # bash-deleted notes stop surfacing. qmd is BM25-only, so prune and full run
  # the identical cleanup+update — never embed.
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

  local i
  for i in $(seq 1 50); do
    [[ "$(wc -l < "$call_log" 2>/dev/null || echo 0)" -ge 2 ]] && break
    sleep 0.1
  done

  run cat "$call_log"
  assert_line "cleanup"
  assert_line "update"
  # Registration calls may precede them; embed must never run.
  refute_line --regexp '^embed'
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

@test "qmd migration uses root project config and confirms the latent root" {
  local pass="$MODULE_DIR/tools/reindex-passive-memories.sh"
  local proj="$WORK/custom project"
  local old_path="$proj/.agents/memory"
  mkdir -p "$proj/.agents/memory/latent" "$proj/.agents/logs" "$old_path"
  printf '{"project_name":"configured-project"}\n' > "$proj/.devbot.project.jsonc"
  local state="$WORK/qmd-state" calls="$WORK/qmd-all-calls" build_calls="$WORK/qmd-build-calls"
  mkdir -p "$state"
  printf '%s\n' "$old_path" > "$state/configured-project"
  : > "$calls"
  : > "$build_calls"
  _make_qmd_migration_stub

  run env PATH="$STUB_DIR:$PATH" \
    QMD_STATE="$state" QMD_TARGET="$proj/.agents/memory/latent" \
    QMD_ALL_CALLS="$calls" QMD_CALL_LOG="$build_calls" \
    DEV_BOT_ROOT="$TEST_DIR/../../../.." \
    bash "$pass" --sync --worktree "$proj"

  assert_success
  assert_output --partial '"status":"rebuilt"'
  [[ "$(cat "$state/configured-project")" == "$proj/.agents/memory/latent" ]]
  grep -q "collection show configured-project" "$calls"
  grep -qx "cleanup" "$build_calls"
  grep -qx "update" "$build_calls"
}

@test "qmd ensure rechecks the collection root before trusting a matching freshness record" {
  local pass="$MODULE_DIR/tools/reindex-passive-memories.sh"
  local proj="$WORK/custom project"
  local old_path="$proj/.agents/memory"
  mkdir -p "$proj/.agents/memory/latent" "$proj/.agents/logs" "$old_path"
  printf '{"project_name":"configured-project"}\n' > "$proj/.devbot.project.jsonc"
  local fingerprint
  fingerprint="$(PATH="$STUB_DIR:$PATH" bash "$pass" --fingerprint "$proj/.agents/memory/latent")"
  printf '{"branch":"","provider":"qmd","tree_sha":"","corpus":"latent","corpus_fingerprint":"%s"}\n' \
    "$fingerprint" > "$proj/.agents/logs/memory-index-branch.json"
  local state="$WORK/qmd-state" calls="$WORK/qmd-all-calls" build_calls="$WORK/qmd-build-calls"
  mkdir -p "$state"
  printf '%s\n' "$old_path" > "$state/configured-project"
  : > "$calls"
  : > "$build_calls"
  _make_qmd_migration_stub

  run env PATH="$STUB_DIR:$PATH" \
    QMD_STATE="$state" QMD_TARGET="$proj/.agents/memory/latent" \
    QMD_ALL_CALLS="$calls" QMD_CALL_LOG="$build_calls" \
    DEV_BOT_ROOT="$TEST_DIR/../../../.." \
    bash "$pass" --ensure --worktree "$proj"

  assert_success
  assert_output --partial '"status":"rebuilt"'
  [[ "$(cat "$state/configured-project")" == "$proj/.agents/memory/latent" ]]
  grep -qx "update" "$build_calls"
}

@test "qmd migration restores the old registration and does not mark freshness when adding the latent root fails" {
  local pass="$MODULE_DIR/tools/reindex-passive-memories.sh"
  local proj="$WORK/custom project"
  local old_path="$proj/.agents/memory"
  mkdir -p "$proj/.agents/memory/latent" "$proj/.agents/logs" "$old_path"
  printf '{"project_name":"configured-project"}\n' > "$proj/.devbot.project.jsonc"
  local state="$WORK/qmd-state" calls="$WORK/qmd-all-calls" build_calls="$WORK/qmd-build-calls"
  mkdir -p "$state"
  printf '%s\n' "$old_path" > "$state/configured-project"
  : > "$calls"
  : > "$build_calls"
  _make_qmd_migration_stub

  run env PATH="$STUB_DIR:$PATH" \
    QMD_STATE="$state" QMD_TARGET="$proj/.agents/memory/latent" \
    QMD_ALL_CALLS="$calls" QMD_CALL_LOG="$build_calls" QMD_FAIL_TARGET_ADD=1 \
    DEV_BOT_ROOT="$TEST_DIR/../../../.." \
    bash "$pass" --sync --worktree "$proj"

  assert_success
  assert_output --partial '"status":"stale"'
  [[ "$(cat "$state/configured-project")" == "$old_path" ]]
  [[ ! -s "$build_calls" ]]
  [[ ! -f "$proj/.agents/logs/memory-index-branch.json" ]]
}

@test "qmd migration fails closed when an existing collection has no readable root" {
  local pass="$MODULE_DIR/tools/reindex-passive-memories.sh"
  local proj="$WORK/custom project"
  local old_path="$proj/.agents/memory/latent"
  mkdir -p "$proj/.agents/memory/latent" "$proj/.agents/logs" "$old_path"
  printf '{"project_name":"configured-project"}\n' > "$proj/.devbot.project.jsonc"
  local state="$WORK/qmd-state" calls="$WORK/qmd-all-calls" build_calls="$WORK/qmd-build-calls"
  mkdir -p "$state"
  printf '%s\n' "$old_path" > "$state/configured-project"
  : > "$calls"
  : > "$build_calls"
  _make_qmd_migration_stub

  run env PATH="$STUB_DIR:$PATH" \
    QMD_STATE="$state" QMD_TARGET="$proj/.agents/memory" \
    QMD_ALL_CALLS="$calls" QMD_CALL_LOG="$build_calls" QMD_OMIT_PATH=1 \
    DEV_BOT_ROOT="$TEST_DIR/../../../.." \
    bash "$pass" --sync --worktree "$proj"

  assert_success
  assert_output --partial '"status":"stale"'
  [[ "$(cat "$state/configured-project")" == "$old_path" ]]
  [[ ! -s "$build_calls" ]]
  [[ ! -f "$proj/.agents/logs/memory-index-branch.json" ]]
}

@test "qmd migration fails closed when a whole-memory collection survives without a latent dir" {
  local pass="$MODULE_DIR/tools/reindex-passive-memories.sh"
  local proj="$WORK/custom project"
  mkdir -p "$proj/.agents/logs"
  printf '{"project_name":"configured-project"}\n' > "$proj/.devbot.project.jsonc"
  local state="$WORK/qmd-state" calls="$WORK/qmd-all-calls" build_calls="$WORK/qmd-build-calls"
  mkdir -p "$state"
  printf '%s\n' "$proj/.agents/memory" > "$state/configured-project"
  : > "$calls"
  : > "$build_calls"
  _make_qmd_migration_stub

  run env PATH="$STUB_DIR:$PATH" \
    QMD_STATE="$state" QMD_TARGET="$proj/.agents/memory/latent" \
    QMD_ALL_CALLS="$calls" QMD_CALL_LOG="$build_calls" \
    DEV_BOT_ROOT="$TEST_DIR/../../../.." \
    bash "$pass" --sync --worktree "$proj"

  assert_success
  assert_output --partial '"status":"stale"'
  [[ "$(cat "$state/configured-project")" == "$proj/.agents/memory" ]]
  [[ ! -s "$build_calls" ]]
  [[ ! -f "$proj/.agents/logs/memory-index-branch.json" ]]
}

@test "qmd migration registers and verifies a missing collection before indexing" {
  local pass="$MODULE_DIR/tools/reindex-passive-memories.sh"
  local proj="$WORK/custom project"
  mkdir -p "$proj/.agents/memory/latent" "$proj/.agents/logs"
  printf '{"project_name":"configured-project"}\n' > "$proj/.devbot.project.jsonc"
  local state="$WORK/qmd-state" calls="$WORK/qmd-all-calls" build_calls="$WORK/qmd-build-calls"
  mkdir -p "$state"
  : > "$calls"
  : > "$build_calls"
  _make_qmd_migration_stub

  run env PATH="$STUB_DIR:$PATH" \
    QMD_STATE="$state" QMD_TARGET="$proj/.agents/memory/latent" \
    QMD_ALL_CALLS="$calls" QMD_CALL_LOG="$build_calls" \
    DEV_BOT_ROOT="$TEST_DIR/../../../.." \
    bash "$pass" --sync --worktree "$proj"

  assert_success
  assert_output --partial '"status":"rebuilt"'
  [[ "$(cat "$state/configured-project")" == "$proj/.agents/memory/latent" ]]
  grep -qx "update" "$build_calls"
}

@test "qmd migration does not record freshness after an unconfirmed collection lookup" {
  local pass="$MODULE_DIR/tools/reindex-passive-memories.sh"
  local proj="$WORK/custom project"
  local old_path="$proj/.agents/memory/latent"
  mkdir -p "$proj/.agents/memory/latent" "$proj/.agents/logs" "$old_path"
  printf '{"project_name":"configured-project"}\n' > "$proj/.devbot.project.jsonc"
  local state="$WORK/qmd-state" calls="$WORK/qmd-all-calls" build_calls="$WORK/qmd-build-calls"
  mkdir -p "$state"
  printf '%s\n' "$old_path" > "$state/configured-project"
  : > "$calls"
  : > "$build_calls"
  _make_qmd_migration_stub

  run env PATH="$STUB_DIR:$PATH" \
    QMD_STATE="$state" QMD_TARGET="$proj/.agents/memory" \
    QMD_ALL_CALLS="$calls" QMD_CALL_LOG="$build_calls" QMD_SHOW_FAIL=1 \
    DEV_BOT_ROOT="$TEST_DIR/../../../.." \
    bash "$pass" --sync --worktree "$proj"

  assert_success
  assert_output --partial '"status":"stale"'
  [[ "$(cat "$state/configured-project")" == "$old_path" ]]
  [[ ! -s "$build_calls" ]]
  [[ ! -f "$proj/.agents/logs/memory-index-branch.json" ]]
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
  assert_output --regexp "\[reindex-memories\] full finished cleanup=0 update=0"
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
  assert_output --regexp "\[reindex-memories\] prune finished cleanup=0 update=0"
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
  # One build per store: the project latent corpus + the global-memories index.
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

@test "passive script: --path resolves the owning project over --worktree" {
  local pass="$MODULE_DIR/tools/reindex-passive-memories.sh"
  local child="$WORK/child" sup="$WORK/sup"
  mkdir -p "$child/.agents/memory/latent" "$child/.mdctx" "$sup/.agents/logs"
  cat > "$WORK/global.jsonc" <<EOF
{ "projects": ["$child"], "devbot_dir": ".agents" }
EOF

  cd "$WORK"
  run env -u DEV_BOT_ROOT \
    DEV_BOT_GLOBAL_CONFIG="$WORK/global.jsonc" \
    XDG_CACHE_HOME="$WORK" \
    PATH="$STUB_DIR:$PATH" \
    bash "$pass" --sync --worktree "$sup" --path "$child/.agents/memory/latent/x.md"

  assert_success
  # The index target is the child, not the polyrepo passed via --worktree.
  [ -f "$child/.agents/logs/memory-index-branch.json" ]
  [ ! -f "$sup/.agents/logs/memory-index-branch.json" ]
}

@test "passive script: --path outside any registered project falls back to --worktree" {
  local pass="$MODULE_DIR/tools/reindex-passive-memories.sh"
  local sup="$WORK/sup"
  mkdir -p "$sup/.agents/memory/latent"
  printf 'x\n' > "$sup/.agents/memory/latent/x.md"
  printf '{ "projects": [], "devbot_dir": ".agents" }\n' > "$WORK/global.jsonc"

  cd "$WORK"
  run env -u DEV_BOT_ROOT \
    DEV_BOT_GLOBAL_CONFIG="$WORK/global.jsonc" \
    XDG_CACHE_HOME="$WORK" \
    PATH="$STUB_DIR:$PATH" \
    bash "$pass" --sync --worktree "$sup" --path "$sup/.agents/memory/latent/x.md"

  assert_success
  [ -f "$sup/.agents/logs/memory-index-branch.json" ]
}

@test "passive script: --path inside the worktree's own project keeps the worktree" {
  # Regression (review F1): a linked worktree at <project>/.agents/worktrees/<slug>
  # resolves to the main registered project, but the reindex must still target
  # the worktree checkout — its vault holds the uncommitted edits.
  local pass="$MODULE_DIR/tools/reindex-passive-memories.sh"
  local proj="$WORK/proj" wt="$WORK/proj/.agents/worktrees/feat-x"
  mkdir -p "$wt/.agents/memory/latent" "$proj/.agents/logs"
  printf '{ "projects": ["%s"], "devbot_dir": ".agents" }\n' "$proj" > "$WORK/global.jsonc"

  cd "$WORK"
  run env -u DEV_BOT_ROOT \
    DEV_BOT_GLOBAL_CONFIG="$WORK/global.jsonc" \
    XDG_CACHE_HOME="$WORK" \
    PATH="$STUB_DIR:$PATH" \
    bash "$pass" --sync --worktree "$wt" --path "$wt/.agents/memory/latent/x.md"

  assert_success
  [ -f "$wt/.agents/logs/memory-index-branch.json" ]
  [ ! -f "$proj/.agents/logs/memory-index-branch.json" ]
}

# ── Configured collections ─────────────────────────────────────────────────────

# Sandbox with the real resolver (so the config is parsed) + a project vault +
# a docs corpus. The resolver is copied into the sandbox devbot root so the
# global store and custom indexes stay isolated from the real install.
_setup_configured_collections() {
  DEVROOT="$WORK/devroot"
  PROJ="$WORK/proj"
  DOCS="$WORK/docs"
  mkdir -p "$DEVROOT/src/_shared" "$DEVROOT/storage/global-memories"
  cp "$MODULE_DIR/../../_shared/memory_collections.py" "$DEVROOT/src/_shared/"
  cp "$MODULE_DIR/../../_shared/read_jsonc.py" "$DEVROOT/src/_shared/"
  mkdir -p "$PROJ/.agents/memory/latent" "$PROJ/.agents/logs" "$DOCS"
  printf 'note\n' > "$PROJ/.agents/memory/latent/a.md"
  printf 'doc\n' > "$DOCS/n.md"
  export DEV_BOT_ROOT="$DEVROOT"
  export MDCTX_CALL_LOG="$WORK/mdctx-calls.log"
  : > "$MDCTX_CALL_LOG"
  cat > "$STUB_DIR/mdctx" <<'SCRIPT'
#!/usr/bin/env bash
echo "$*" >> "${MDCTX_CALL_LOG:?}"
SCRIPT
  chmod +x "$STUB_DIR/mdctx"
}

@test "configured collections: mdctx builds a custom collection index" {
  export DEVBOT_MEMORY_SEARCH_PROVIDER=mdctx
  _setup_configured_collections
  printf '{"memory_collections": {"notes": {"path": "%s"}}}\n' "$DOCS" \
    > "$PROJ/.devbot.project.jsonc"

  cd "$PROJ"
  run env PATH="$STUB_DIR:$PATH" bash "$TOOL" --sync
  cd "$WORK"

  assert_success
  grep -q "storage/.mdctx/collections/" "$MDCTX_CALL_LOG"
}

@test "configured collections: adding one forces an --ensure rebuild" {
  export DEVBOT_MEMORY_SEARCH_PROVIDER=mdctx
  _setup_configured_collections
  printf '{}\n' > "$PROJ/.devbot.project.jsonc"

  cd "$PROJ"
  run env PATH="$STUB_DIR:$PATH" bash "$TOOL" --sync
  assert_success
  before="$(wc -l < "$MDCTX_CALL_LOG")"

  run env PATH="$STUB_DIR:$PATH" bash "$TOOL" --ensure
  assert_success
  [ "$(wc -l < "$MDCTX_CALL_LOG")" -eq "$before" ] \
    || fail "unexpected rebuild with an unchanged collection set"

  printf '{"memory_collections": {"notes": {"path": "%s"}}}\n' "$DOCS" \
    > "$PROJ/.devbot.project.jsonc"
  run env PATH="$STUB_DIR:$PATH" bash "$TOOL" --ensure
  cd "$WORK"

  assert_success
  [ "$(wc -l < "$MDCTX_CALL_LOG")" -gt "$before" ]
  grep -q "storage/.mdctx/collections/" "$MDCTX_CALL_LOG"
}

@test "configured collections: qmd registers a custom collection by name" {
  export DEVBOT_MEMORY_SEARCH_PROVIDER=qmd
  _setup_configured_collections
  printf '{"memory_collections": {"notes": {"path": "%s"}}}\n' "$DOCS" \
    > "$PROJ/.devbot.project.jsonc"

  # Name-keyed fake qmd: collection state lives in $QMD_STATE_DIR/<name>.
  export QMD_STATE_DIR="$WORK/qmd-state"
  export QMD_ALL_CALLS="$WORK/qmd-calls.log"
  mkdir -p "$QMD_STATE_DIR"
  : > "$QMD_ALL_CALLS"
  cat > "$STUB_DIR/qmd" <<'SCRIPT'
#!/usr/bin/env bash
echo "$*" >> "${QMD_ALL_CALLS:?}"
case "${1:-} ${2:-}" in
  "collection show")
    path="$(cat "${QMD_STATE_DIR:?}/${3:-}" 2>/dev/null || true)"
    [[ -n "$path" ]] || exit 1
    printf 'Path: %s\n' "$path"
    ;;
  "collection add")
    shift 2
    path=""; name=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --name) name="$2"; shift 2 ;;
        *) [[ -z "$path" ]] && path="$1"; shift ;;
      esac
    done
    printf '%s\n' "$path" > "${QMD_STATE_DIR:?}/${name}"
    ;;
  "collection remove") rm -f "${QMD_STATE_DIR:?}/${3:-}" ;;
esac
SCRIPT
  chmod +x "$STUB_DIR/qmd"

  cd "$PROJ"
  run env PATH="$STUB_DIR:$PATH" bash "$TOOL" --sync
  cd "$WORK"

  assert_success
  grep -q "collection add ${DOCS} --name dev-bot-custom-" "$QMD_ALL_CALLS"
}

@test "configured collections: a reserved key aborts before the engine runs" {
  export DEVBOT_MEMORY_SEARCH_PROVIDER=mdctx
  _setup_configured_collections
  printf '{"memory_collections": {"global": {"path": "/x"}}}\n' \
    > "$PROJ/.devbot.project.jsonc"

  cd "$PROJ"
  run env PATH="$STUB_DIR:$PATH" bash "$TOOL" --sync
  cd "$WORK"

  assert_failure
  assert_output --partial "may only be set in the global config"
  [ ! -s "$MDCTX_CALL_LOG" ] || fail "engine ran despite an invalid collection config"
}

@test "configured collections: a custom-corpus edit forces an --ensure rebuild" {
  export DEVBOT_MEMORY_SEARCH_PROVIDER=mdctx
  _setup_configured_collections
  printf '{"memory_collections": {"notes": {"path": "%s"}}}\n' "$DOCS" \
    > "$PROJ/.devbot.project.jsonc"

  cd "$PROJ"
  run env PATH="$STUB_DIR:$PATH" bash "$TOOL" --sync
  assert_success
  before="$(wc -l < "$MDCTX_CALL_LOG")"

  printf 'edited\n' >> "$DOCS/n.md"
  run env PATH="$STUB_DIR:$PATH" bash "$TOOL" --ensure
  cd "$WORK"

  assert_success
  [ "$(wc -l < "$MDCTX_CALL_LOG")" -gt "$before" ] \
    || fail "an edit under a custom collection did not trigger a rebuild"
}

@test "configured collections: an edit outside every collection is skipped" {
  export DEVBOT_MEMORY_SEARCH_PROVIDER=mdctx
  _setup_configured_collections
  printf '{"memory_collections": {"notes": {"path": "%s"}}}\n' "$DOCS" \
    > "$PROJ/.devbot.project.jsonc"
  printf 'readme\n' > "$WORK/README.md"

  cd "$PROJ"
  run env PATH="$STUB_DIR:$PATH" bash "$TOOL" --sync --path "$WORK/README.md"
  cd "$WORK"

  assert_success
  assert_output --partial '"status":"skipped"'
  [ ! -s "$MDCTX_CALL_LOG" ] || fail "an unrelated markdown edit triggered a build"
}

@test "configured collections: qmd honors an overridden built-in project path" {
  export DEVBOT_MEMORY_SEARCH_PROVIDER=qmd
  _setup_configured_collections
  local alt="$WORK/alt-corpus"
  mkdir -p "$alt"
  printf 'alt\n' > "$alt/a.md"
  printf '{"project_name": "proj", "memory_collections": {"project": {"path": "%s"}}}\n' \
    "$alt" > "$PROJ/.devbot.project.jsonc"

  export QMD_STATE_DIR="$WORK/qmd-state"
  export QMD_ALL_CALLS="$WORK/qmd-calls.log"
  mkdir -p "$QMD_STATE_DIR"
  : > "$QMD_ALL_CALLS"
  cat > "$STUB_DIR/qmd" <<'SCRIPT'
#!/usr/bin/env bash
echo "$*" >> "${QMD_ALL_CALLS:?}"
case "${1:-} ${2:-}" in
  "collection show")
    path="$(cat "${QMD_STATE_DIR:?}/${3:-}" 2>/dev/null || true)"
    [[ -n "$path" ]] || exit 1
    printf 'Path: %s\n' "$path"
    ;;
  "collection add")
    shift 2
    path=""; name=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --name) name="$2"; shift 2 ;;
        *) [[ -z "$path" ]] && path="$1"; shift ;;
      esac
    done
    printf '%s\n' "$path" > "${QMD_STATE_DIR:?}/${name}"
    ;;
  "collection remove") rm -f "${QMD_STATE_DIR:?}/${3:-}" ;;
esac
SCRIPT
  chmod +x "$STUB_DIR/qmd"

  cd "$PROJ"
  run env PATH="$STUB_DIR:$PATH" bash "$TOOL" --sync
  cd "$WORK"

  assert_success
  grep -q "collection add ${alt} --name proj" "$QMD_ALL_CALLS"
}

@test "qmd migration allows a changed external project root" {
  local pass="$MODULE_DIR/tools/reindex-passive-memories.sh"
  local proj="$WORK/custom project"
  local old_root="$WORK/vault-one" new_root="$WORK/vault-two"
  mkdir -p "$proj/.agents/logs" "$old_root" "$new_root"
  printf '{"project_name":"configured-project","memory_collections":{"project":{"path":"%s"}}}\n' \
    "$new_root" > "$proj/.devbot.project.jsonc"
  printf '{"project_collection_path":"%s"}\n' "$old_root" \
    > "$proj/.agents/logs/memory-index-branch.json"
  local state="$WORK/qmd-state" calls="$WORK/qmd-all-calls" build_calls="$WORK/qmd-build-calls"
  mkdir -p "$state"
  printf '%s\n' "$old_root" > "$state/configured-project"
  : > "$calls"
  : > "$build_calls"
  _make_qmd_migration_stub

  run env PATH="$STUB_DIR:$PATH" \
    QMD_STATE="$state" QMD_TARGET="$new_root" \
    QMD_ALL_CALLS="$calls" QMD_CALL_LOG="$build_calls" \
    DEV_BOT_ROOT="$TEST_DIR/../../../.." \
    bash "$pass" --sync --worktree "$proj"

  assert_success
  assert_output --partial '"status":"rebuilt"'
  [[ "$(cat "$state/configured-project")" == "$new_root" ]]
}

@test "qmd migration refuses a nested worktree's registration" {
  local pass="$MODULE_DIR/tools/reindex-passive-memories.sh"
  local proj="$WORK/custom project"
  local wt="$proj/.agents/worktrees/feat-x"
  mkdir -p "$proj/.agents/memory/latent" "$proj/.agents/logs" \
    "$wt/.agents/memory/latent"
  printf '{"project_name":"configured-project"}\n' > "$proj/.devbot.project.jsonc"
  printf '{"project_collection_path":"%s"}\n' "$proj/.agents/memory" \
    > "$proj/.agents/logs/memory-index-branch.json"
  local state="$WORK/qmd-state" calls="$WORK/qmd-all-calls" build_calls="$WORK/qmd-build-calls"
  mkdir -p "$state"
  printf '%s\n' "$wt/.agents/memory" > "$state/configured-project"
  : > "$calls"
  : > "$build_calls"
  _make_qmd_migration_stub

  run env PATH="$STUB_DIR:$PATH" \
    QMD_STATE="$state" QMD_TARGET="$proj/.agents/memory" \
    QMD_ALL_CALLS="$calls" QMD_CALL_LOG="$build_calls" \
    DEV_BOT_ROOT="$TEST_DIR/../../../.." \
    bash "$pass" --sync --worktree "$proj"

  assert_success
  assert_output --partial '"status":"stale"'
  [[ "$(cat "$state/configured-project")" == "$wt/.agents/memory" ]]
}

@test "qmd reindex keeps the previous project ownership when the new root is missing" {
  local pass="$MODULE_DIR/tools/reindex-passive-memories.sh"
  local proj="$WORK/custom project"
  local old_root="$WORK/vault-one"
  mkdir -p "$proj/.agents/logs" "$old_root"
  printf '{"project_name":"configured-project","memory_collections":{"project":{"path":"%s"}}}\n' \
    "$WORK/does-not-exist" > "$proj/.devbot.project.jsonc"
  printf '{"project_collection_path":"%s"}\n' "$old_root" \
    > "$proj/.agents/logs/memory-index-branch.json"
  local state="$WORK/qmd-state" calls="$WORK/qmd-all-calls" build_calls="$WORK/qmd-build-calls"
  mkdir -p "$state"
  printf '%s\n' "$old_root" > "$state/configured-project"
  : > "$calls"
  : > "$build_calls"
  _make_qmd_migration_stub

  run env PATH="$STUB_DIR:$PATH" \
    QMD_STATE="$state" QMD_TARGET="$WORK/does-not-exist" \
    QMD_ALL_CALLS="$calls" QMD_CALL_LOG="$build_calls" \
    DEV_BOT_ROOT="$TEST_DIR/../../../.." \
    bash "$pass" --sync --worktree "$proj"

  assert_success
  assert_output --partial '"status":"rebuilt"'
  python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["project_collection_path"] == sys.argv[2]' \
    "$proj/.agents/logs/memory-index-branch.json" "$old_root"
}

@test "qmd reindex persists repoint ownership when update fails" {
  local pass="$MODULE_DIR/tools/reindex-passive-memories.sh"
  local proj="$WORK/custom project"
  local root_a="$WORK/vault-a" root_b="$WORK/vault-b"
  mkdir -p "$proj/.agents/logs" "$root_a" "$root_b"
  printf '{"project_collection_path":"%s"}\n' "$root_a" \
    > "$proj/.agents/logs/memory-index-branch.json"
  printf '{"project_name":"configured-project","memory_collections":{"project":{"path":"%s"}}}\n' \
    "$root_b" > "$proj/.devbot.project.jsonc"
  local state="$WORK/qmd-state" calls="$WORK/qmd-all-calls" build_calls="$WORK/qmd-build-calls"
  mkdir -p "$state"
  printf '%s\n' "$root_a" > "$state/configured-project"
  : > "$calls"
  : > "$build_calls"
  _make_qmd_migration_stub

  run env PATH="$STUB_DIR:$PATH" \
    QMD_STATE="$state" QMD_TARGET="$root_b" \
    QMD_ALL_CALLS="$calls" QMD_CALL_LOG="$build_calls" QMD_UPDATE_FAIL=1 \
    DEV_BOT_ROOT="$TEST_DIR/../../../.." \
    bash "$pass" --sync --worktree "$proj"

  assert_success
  assert_output --partial '"status":"stale"'
  [[ "$(cat "$state/configured-project")" == "$root_b" ]]
  python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["project_collection_path"] == sys.argv[2]' \
    "$proj/.agents/logs/memory-index-branch.json" "$root_b"

  printf '{"project_name":"configured-project","memory_collections":{"project":{"path":"%s"}}}\n' \
    "$root_a" > "$proj/.devbot.project.jsonc"
  run env PATH="$STUB_DIR:$PATH" \
    QMD_STATE="$state" QMD_TARGET="$root_a" \
    QMD_ALL_CALLS="$calls" QMD_CALL_LOG="$build_calls" \
    DEV_BOT_ROOT="$TEST_DIR/../../../.." \
    bash "$pass" --sync --worktree "$proj"

  assert_success
  assert_output --partial '"status":"rebuilt"'
  [[ "$(cat "$state/configured-project")" == "$root_a" ]]
}

@test "qmd migration releases a custom registration at the new project root" {
  local pass="$MODULE_DIR/tools/reindex-passive-memories.sh"
  local proj="$WORK/custom project"
  local old_root="$WORK/old-root" docs="$WORK/docs"
  mkdir -p "$proj/.agents/logs" "$old_root" "$docs"
  printf '{"project_name":"configured-project","memory_collections":{"project":{"path":"%s"}}}\n' \
    "$docs" > "$proj/.devbot.project.jsonc"
  printf '{"project_collection_path":"%s"}\n' "$old_root" \
    > "$proj/.agents/logs/memory-index-branch.json"
  local custom
  custom="dev-bot-custom-$(python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.argv[1].encode()).hexdigest()[:12])' "$docs")"
  local state="$WORK/qmd-state" calls="$WORK/qmd-all-calls" build_calls="$WORK/qmd-build-calls"
  mkdir -p "$state"
  printf '%s\n' "$old_root" > "$state/configured-project"
  printf '%s\n' "$docs" > "$state/$custom"
  : > "$calls"
  : > "$build_calls"
  _make_qmd_migration_stub

  run env PATH="$STUB_DIR:$PATH" \
    QMD_STATE="$state" QMD_TARGET="$docs" \
    QMD_ALL_CALLS="$calls" QMD_CALL_LOG="$build_calls" \
    DEV_BOT_ROOT="$TEST_DIR/../../../.." \
    bash "$pass" --sync --worktree "$proj"

  assert_success
  assert_output --partial '"status":"rebuilt"'
  [[ "$(cat "$state/configured-project")" == "$docs" ]]
  [[ ! -f "$state/$custom" ]]
}

@test "qmd migration releases a custom registration at the latent project root" {
  local pass="$MODULE_DIR/tools/reindex-passive-memories.sh"
  local proj="$WORK/custom project"
  local memory="$proj/.agents/memory"
  local target="$memory/latent"
  mkdir -p "$target" "$proj/.agents/logs"
  printf '{"project_name":"configured-project"}\n' > "$proj/.devbot.project.jsonc"
  local custom
  custom="dev-bot-custom-$(python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.argv[1].encode()).hexdigest()[:12])' "$target")"
  local state="$WORK/qmd-state" calls="$WORK/qmd-all-calls" build_calls="$WORK/qmd-build-calls"
  mkdir -p "$state"
  printf '%s\n' "$memory" > "$state/configured-project"
  printf '%s\n' "$target" > "$state/$custom"
  : > "$calls"
  : > "$build_calls"
  _make_qmd_migration_stub

  run env PATH="$STUB_DIR:$PATH" \
    QMD_STATE="$state" QMD_TARGET="$target" \
    QMD_ALL_CALLS="$calls" QMD_CALL_LOG="$build_calls" \
    DEV_BOT_ROOT="$TEST_DIR/../../../.." \
    bash "$pass" --sync --worktree "$proj"

  assert_success
  assert_output --partial '"status":"rebuilt"'
  [[ "$(cat "$state/configured-project")" == "$target" ]]
  [[ ! -f "$state/$custom" ]]
}

@test "qmd ensure rebuilds when a global registration points elsewhere" {
  local pass="$MODULE_DIR/tools/reindex-passive-memories.sh"
  local proj="$WORK/custom project"
  local memory="$proj/.agents/memory"
  mkdir -p "$memory/latent" "$proj/.agents/logs"
  printf '{"project_name":"configured-project"}\n' > "$proj/.devbot.project.jsonc"
  local state="$WORK/qmd-state" calls="$WORK/qmd-all-calls" build_calls="$WORK/qmd-build-calls"
  mkdir -p "$state"
  printf '%s\n' "$memory/latent" > "$state/configured-project"
  printf '%s\n' "$DEV_BOT_ROOT/storage/global-memories" > "$state/dev-bot-global"
  : > "$calls"
  : > "$build_calls"
  _make_qmd_migration_stub

  run env PATH="$STUB_DIR:$PATH" \
    QMD_STATE="$state" QMD_TARGET="$memory" \
    QMD_ALL_CALLS="$calls" QMD_CALL_LOG="$build_calls" \
    DEV_BOT_ROOT="$TEST_DIR/../../../.." \
    bash "$pass" --sync --worktree "$proj"
  assert_success
  local before
  before="$(wc -l < "$build_calls")"

  printf '%s\n' "$WORK/other-global" > "$state/dev-bot-global"
  run env PATH="$STUB_DIR:$PATH" \
    QMD_STATE="$state" QMD_TARGET="$memory" \
    QMD_ALL_CALLS="$calls" QMD_CALL_LOG="$build_calls" \
    DEV_BOT_ROOT="$TEST_DIR/../../../.." \
    bash "$pass" --ensure --worktree "$proj"

  assert_success
  [ "$(wc -l < "$build_calls")" -gt "$before" ] \
    || fail "a mismatched global registration did not force a rebuild"
}
