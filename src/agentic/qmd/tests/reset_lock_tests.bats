#!/usr/bin/env bats
# =============================================================================
# src/agentic/qmd/tests/reset_lock_tests.bats
# Tests for the shared-store lock in qmd reset.sh.
#
# `devbot init --all --full -j N` runs this reset once per project, in
# parallel. Collection removal and context removal both mutate the
# machine-wide qmd store, so the reset must hold the same build lock the init
# and reindex paths hold — otherwise concurrent writers crash the store.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  RESET="${MODULE_DIR}/reset.sh"

  WORK="$(mktemp -d)"
  PROJECT="${WORK}/proj"
  STUB="${WORK}/bin"
  mkdir -p "$PROJECT" "$STUB" "${WORK}/cache/devbot"

  cat > "$STUB/qmd" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${QMD_CALLS}"
exit 0
STUB
  chmod +x "$STUB/qmd"

  export PATH="$STUB:$PATH"
  export QMD_CALLS="${WORK}/calls.log"
  export XDG_CACHE_HOME="${WORK}/cache"
  export LOCK_FILE="${WORK}/cache/devbot/reindex-memories.lock"
}

teardown() {
  rm -rf "$WORK" 2>/dev/null || true
}

# Hold the build lock in another process for a few seconds.
_hold_lock() {
  python3 - "$LOCK_FILE" <<'PY' &
import fcntl, sys, time
f = open(sys.argv[1], "w")
fcntl.flock(f, fcntl.LOCK_EX)
time.sleep(5)
PY
  HOLDER=$!
  sleep 0.5
}

@test "reset --full skips the shared store when the build lock is held" {
  _hold_lock

  DEVBOT_INDEX_LOCK_WAIT=1 run bash "$RESET" "$PROJECT" --full
  wait "$HOLDER"

  assert_success
  assert_output --partial "could not take the memory index lock"
  run test -e "$QMD_CALLS"
  assert_failure
}

@test "reset --full removes the collection once it holds the lock" {
  run bash "$RESET" "$PROJECT" --full

  assert_success
  run cat "$QMD_CALLS"
  assert_output --partial "collection remove"
}

@test "a plain reset never touches the shared store or the lock" {
  run bash "$RESET" "$PROJECT"

  assert_success
  run test -e "$QMD_CALLS"
  assert_failure
}
