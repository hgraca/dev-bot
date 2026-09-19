#!/usr/bin/env bats
# Tests for branch-aware memory indexing.
#
# The reindex engine records the indexed {branch, provider, tree_sha} to
# <project>/<devbot-dir>/logs/memory-index-branch.json and, with --ensure,
# rebuilds only when the record no longer matches the current checkout. These
# tests pin that contract at the engine boundary (the query path delegates to
# it); the record format is part of the interface.

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  TOOL="$MODULE_DIR/tools/reindex-passive-memories.sh"

  WORK="$(mktemp -d)"
  export XDG_CACHE_HOME="$WORK"

  # Pin the mdctx engine so dispatch is deterministic (default engine is mdctx,
  # but the machine config must not leak in).
  export DEVBOT_MEMORY_SEARCH_PROVIDER=mdctx

  # Sandbox devbot root: the global store the engine also builds, isolated from
  # the real install. It deliberately has no src/ — provider/project-dir
  # resolution falls back to defaults, exactly like a minimal install.
  export DEV_BOT_ROOT="$WORK/devroot"
  mkdir -p "$DEV_BOT_ROOT/storage/global-memories"

  # Fake mdctx that records its argv so a test can tell whether a build ran.
  STUB_DIR="$WORK/bin"
  mkdir -p "$STUB_DIR"
  cat > "$STUB_DIR/mdctx" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  echo "0.1.0"
  exit 0
fi
echo "$*" >> "${MDCTX_CALL_LOG:?MDCTX_CALL_LOG unset}"
exit 0
SCRIPT
  chmod +x "$STUB_DIR/mdctx"

  export MDCTX_CALL_LOG="$WORK/mdctx-calls.log"
  : > "$MDCTX_CALL_LOG"
}

teardown() {
  rm -rf "$WORK"
}

# ── Fixtures ─────────────────────────────────────────────────────────────────

# A git-backed project with a committed latent vault (so the vault tree sha
# resolves). Default branch is forced to main so assertions are deterministic.
_make_git_project() {
  local proj="$1"
  mkdir -p "$proj/.agents/memory/latent" "$proj/.agents/logs"
  printf 'note main\n' > "$proj/.agents/memory/latent/note.md"
  git -C "$proj" init -q
  git -C "$proj" symbolic-ref HEAD refs/heads/main
  git -C "$proj" config user.email test@example.com
  git -C "$proj" config user.name Test
  git -C "$proj" add -A
  git -C "$proj" commit -qm "init vault"
}

_record_path() { echo "$1/.agents/logs/memory-index-branch.json"; }

_record_field() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2],""))' "$1" "$2"
}

_vault_tree_sha() {
  git -C "$1" rev-parse "HEAD:.agents/memory/latent"
}

_write_record() {
  python3 -c '
import json, sys
json.dump(
    {
        "branch": sys.argv[2],
        "provider": sys.argv[3],
        "tree_sha": sys.argv[4],
        "recorded_at": "2026-01-01T00:00:00Z",
    },
    open(sys.argv[1], "w"),
)
' "$1" "$2" "$3" "$4"
}

# ── AC1: missing record → build + record ─────────────────────────────────────

@test "--ensure: builds and records the branch when no record exists" {
  local proj="$WORK/project-record"
  _make_git_project "$proj"
  local record
  record="$(_record_path "$proj")"

  cd "$proj"
  run env PATH="$STUB_DIR:$PATH" bash "$TOOL" --ensure
  cd "$WORK"

  assert_success
  [ -f "$record" ] || fail "no branch record written"
  [ "$(_record_field "$record" branch)" = "main" ]
  [ "$(_record_field "$record" provider)" = "mdctx" ]
  [ "$(_record_field "$record" tree_sha)" = "$(_vault_tree_sha "$proj")" ]
  grep -q "build" "$MDCTX_CALL_LOG"
}

# ── AC4: current record → no build ───────────────────────────────────────────

@test "--ensure: no-op when branch, provider and tree_sha all match" {
  local proj="$WORK/project-current"
  _make_git_project "$proj"
  _write_record "$(_record_path "$proj")" main mdctx "$(_vault_tree_sha "$proj")"

  cd "$proj"
  run env PATH="$STUB_DIR:$PATH" bash "$TOOL" --ensure
  cd "$WORK"

  assert_success
  # No engine invocation at all — the fast path must not rebuild.
  [ ! -s "$MDCTX_CALL_LOG" ] || fail "expected no build, got: $(cat "$MDCTX_CALL_LOG")"
}

# ── AC1: branch change → rebuild, record rewritten ───────────────────────────

@test "--ensure: rebuilds and rewrites the record when the branch changed" {
  local proj="$WORK/project-branch"
  _make_git_project "$proj"
  _write_record "$(_record_path "$proj")" main mdctx "$(_vault_tree_sha "$proj")"

  git -C "$proj" checkout -q -b feature/other
  cd "$proj"
  run env PATH="$STUB_DIR:$PATH" bash "$TOOL" --ensure
  cd "$WORK"

  assert_success
  grep -q "build" "$MDCTX_CALL_LOG"
  [ "$(_record_field "$(_record_path "$proj")" branch)" = "feature/other" ]
}

# ── AC2: same branch, vault content changed → rebuild ────────────────────────

@test "--ensure: rebuilds when the vault tree sha changed on the same branch" {
  local proj="$WORK/project-tree"
  _make_git_project "$proj"
  _write_record "$(_record_path "$proj")" main mdctx "$(_vault_tree_sha "$proj")"

  printf 'another note\n' > "$proj/.agents/memory/latent/another.md"
  git -C "$proj" add -A
  git -C "$proj" commit -qm "add vault note"

  cd "$proj"
  run env PATH="$STUB_DIR:$PATH" bash "$TOOL" --ensure
  cd "$WORK"

  assert_success
  grep -q "build" "$MDCTX_CALL_LOG"
  [ "$(_record_field "$(_record_path "$proj")" tree_sha)" = "$(_vault_tree_sha "$proj")" ]
}

# ── AC3: unrelated commit → no rebuild ───────────────────────────────────────

@test "--ensure: no-op for an unrelated commit on the same branch" {
  local proj="$WORK/project-unrelated"
  _make_git_project "$proj"
  _write_record "$(_record_path "$proj")" main mdctx "$(_vault_tree_sha "$proj")"

  printf 'readme\n' > "$proj/README.md"
  git -C "$proj" add README.md
  git -C "$proj" commit -qm "docs: add readme"

  cd "$proj"
  run env PATH="$STUB_DIR:$PATH" bash "$TOOL" --ensure
  cd "$WORK"

  assert_success
  [ ! -s "$MDCTX_CALL_LOG" ] || fail "expected no build, got: $(cat "$MDCTX_CALL_LOG")"
}

# ── engine switch → rebuild ──────────────────────────────────────────────────

@test "--ensure: rebuilds when the recorded provider differs from the current one" {
  local proj="$WORK/project-provider"
  _make_git_project "$proj"
  # Recorded engine is qmd; current engine is mdctx → the mdctx index is absent.
  _write_record "$(_record_path "$proj")" main qmd "$(_vault_tree_sha "$proj")"

  cd "$proj"
  run env PATH="$STUB_DIR:$PATH" bash "$TOOL" --ensure
  cd "$WORK"

  assert_success
  grep -q "build" "$MDCTX_CALL_LOG"
  [ "$(_record_field "$(_record_path "$proj")" provider)" = "mdctx" ]
}

# ── AC5: rebuild failure is fail-open ────────────────────────────────────────

@test "--ensure: rebuild failure warns on stderr, reports stale JSON on stdout" {
  local proj="$WORK/project-fail"
  _make_git_project "$proj"
  cat > "$STUB_DIR/mdctx" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then echo "0.1.0"; exit 0; fi
echo "boom" >&2
exit 1
SCRIPT
  chmod +x "$STUB_DIR/mdctx"

  cd "$proj"
  env PATH="$STUB_DIR:$PATH" bash "$TOOL" --ensure \
    >"$WORK/ensure-out.json" 2>"$WORK/ensure-err.txt"
  local rc=$?
  cd "$WORK"

  # Fail-open: exit 0, caller proceeds on the existing index.
  [ "$rc" -eq 0 ] || fail "expected exit 0 (fail-open), got $rc"
  # stdout is the JSON status contract — it must parse, and must not claim
  # freshness. (The old bug: the WARN polluted stdout, so a json.load by the
  # caller failed and was read as success.)
  run python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["status"])' \
    "$WORK/ensure-out.json"
  assert_success
  assert_output "stale"
  # The warning must be visible to the caller on stderr, not swallowed.
  run cat "$WORK/ensure-err.txt"
  assert_output --partial "WARN"
  [ ! -f "$(_record_path "$proj")" ] || fail "recorded a failed build"
}

# ── --sync: foreground build ─────────────────────────────────────────────────

@test "--sync: builds in the foreground and records the branch" {
  local proj="$WORK/project-sync"
  _make_git_project "$proj"

  cd "$proj"
  run env PATH="$STUB_DIR:$PATH" bash "$TOOL" --sync
  cd "$WORK"

  assert_success
  # Foreground: the build is already recorded when --sync returns.
  grep -q "build" "$MDCTX_CALL_LOG"
  [ -f "$(_record_path "$proj")" ] || fail "no branch record written"
  # Foreground mode leaves no background pid behind.
  [ ! -f "$WORK/devbot/reindex-memories.pid" ]
}

# ── AC8: the record is state, not a session log ──────────────────────────────

@test "branch record survives session log rotation" {
  local proj="$WORK/project-rotate"
  _make_git_project "$proj"
  _write_record "$(_record_path "$proj")" main mdctx deadbeef

  # Rotation moves *.log into rotated/; the JSON record must stay put.
  bash -c 'source "'"$MODULE_DIR"'/functions.sh"; _devbot_rotate_session_logs "'"$proj"'"'

  [ -f "$(_record_path "$proj")" ] || fail "rotation moved the branch record away"
}

# ── Parser robustness ────────────────────────────────────────────────────────

@test "valueless --file / --worktree terminate instead of hanging" {
  # `shift 2` with one arg left fails and leaves $1 unchanged — the parser used
  # to spin forever on a valueless flag (reachable from an agent-supplied MCP
  # arg). Any non-124 exit proves the loop terminates.
  local proj="$WORK/project-args"
  _make_git_project "$proj"

  cd "$proj"
  run env PATH="$STUB_DIR:$PATH" timeout 10 bash "$TOOL" --file
  local file_status="$status"
  run env PATH="$STUB_DIR:$PATH" timeout 10 bash "$TOOL" --worktree
  local worktree_status="$status"
  cd "$WORK"

  [ "$file_status" -ne 124 ] || fail "parser hung on a valueless --file"
  [ "$worktree_status" -ne 124 ] || fail "parser hung on a valueless --worktree"
}

# ── Build lock: foreground builds never run unlocked ─────────────────────────

# Hold the build lock (the flock the background job keeps via its inherited
# fd 200) for longer than the ensure cap.
_hold_build_lock() {
  mkdir -p "$WORK/devbot"
  # stdio to /dev/null: otherwise the background child inherits the caller's
  # `$(...)` pipe and the substitution would block until the child exits.
  (
    exec 200>"$WORK/devbot/reindex-memories.lock"
    { flock -n 200 2>/dev/null || python3 -c 'import fcntl; fcntl.flock(200, fcntl.LOCK_EX|fcntl.LOCK_NB)' 2>/dev/null; } || exit 1
    sleep 5
  ) >/dev/null 2>&1 &
  echo $!
}

@test "--ensure: returns stale and does not build when the build lock is held" {
  local proj="$WORK/project-lock-ensure"
  _make_git_project "$proj"
  local holder
  holder="$(_hold_build_lock)"
  sleep 0.3

  cd "$proj"
  run env PATH="$STUB_DIR:$PATH" REINDEX_ENSURE_WAIT=1 bash "$TOOL" --ensure
  cd "$WORK"
  kill "$holder" 2>/dev/null || true

  assert_success
  assert_output --partial '"status":"stale"'
  assert_output --partial "build-lock-timeout"
  # An unlocked build must never happen: no engine call, no record.
  [ ! -s "$MDCTX_CALL_LOG" ] || fail "built while the lock was held"
  [ ! -f "$(_record_path "$proj")" ] || fail "recorded while the lock was held"
}

@test "--sync: returns stale and does not build when the build lock is held" {
  local proj="$WORK/project-lock-sync"
  _make_git_project "$proj"
  local holder
  holder="$(_hold_build_lock)"
  sleep 0.3

  cd "$proj"
  run env PATH="$STUB_DIR:$PATH" REINDEX_ENSURE_WAIT=1 bash "$TOOL" --sync
  cd "$WORK"
  kill "$holder" 2>/dev/null || true

  assert_success
  assert_output --partial '"status":"stale"'
  assert_output --partial "build-lock-timeout"
  [ ! -s "$MDCTX_CALL_LOG" ] || fail "built while the lock was held"
}

# ── Record snapshot: names the built checkout, not the current one ───────────

@test "record describes the checkout the build started from (HEAD moved mid-build)" {
  local proj="$WORK/project-race"
  _make_git_project "$proj"
  local record
  record="$(_record_path "$proj")"

  # The stub switches the repo to another branch while the engine "runs",
  # simulating a branch switch during a build.
  cat > "$STUB_DIR/mdctx" <<SCRIPT
#!/usr/bin/env bash
if [[ "\${1:-}" == "--version" ]]; then echo "0.1.0"; exit 0; fi
echo "\$*" >> "\${MDCTX_CALL_LOG:?}"
git -C "$proj" checkout -q -b moved-mid-build 2>/dev/null || true
exit 0
SCRIPT
  chmod +x "$STUB_DIR/mdctx"

  cd "$proj"
  run env PATH="$STUB_DIR:$PATH" bash "$TOOL" --sync
  cd "$WORK"

  assert_success
  # The build started on main; the record must not claim the branch HEAD moved to.
  [ "$(_record_field "$record" branch)" = "main" ] \
    || fail "record captured the post-build branch: $(_record_field "$record" branch)"
}

# ── Record write is atomic / does not follow a symlink ───────────────────────

@test "record write replaces a symlink at the record path instead of following it" {
  local proj="$WORK/project-symlink"
  _make_git_project "$proj"
  mkdir -p "$proj/.agents/logs"
  local victim="$WORK/victim.txt"
  printf 'do not touch\n' > "$victim"
  ln -s "$victim" "$(_record_path "$proj")"

  cd "$proj"
  run env PATH="$STUB_DIR:$PATH" bash "$TOOL" --sync
  cd "$WORK"

  assert_success
  # Write-then-rename swaps the symlink for a real record; it must never be
  # used as the write target.
  [ ! -L "$(_record_path "$proj")" ] || fail "record path is still a symlink"
  run cat "$victim"
  assert_output "do not touch"
  [ "$(_record_field "$(_record_path "$proj")" branch)" = "main" ]
}

# ── Record escaping ──────────────────────────────────────────────────────────

@test "record stays valid JSON for a branch name containing a double quote" {
  local proj="$WORK/project-quote"
  _make_git_project "$proj"
  # A double quote is legal in a git ref name (check-ref-format accepts it), so
  # raw interpolation would emit a malformed record.
  git -C "$proj" checkout -q -b 'feat"quote'

  cd "$proj"
  run env PATH="$STUB_DIR:$PATH" bash "$TOOL" --sync
  cd "$WORK"
  assert_success

  run python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["branch"])' \
    "$(_record_path "$proj")"
  assert_success
  assert_output 'feat"quote'
}
