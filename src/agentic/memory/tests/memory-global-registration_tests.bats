#!/usr/bin/env bats
# =============================================================================
# src/agentic/memory/tests/memory-global-registration_tests.bats
# Tests for the shared global-store registration split out of _scaffold_vault.
#
# The global memory index/collection is machine-wide state. `devbot init
# --all -j N` runs several workers at once, so each worker defers it
# (DEV_BOT_DEFER_GLOBAL_MEMORY=1) and the parent rebuilds it once through
# `memory/init.sh --global-only`. These tests pin all three behaviours:
#   - the normal path still registers;
#   - the deferred path scaffolds the project but skips the shared store;
#   - `--global-only` registers without touching a project vault.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../../.." && pwd)"
  INIT="${PROJECT_ROOT}/src/agentic/memory/init.sh"

  WORK="$(mktemp -d)"
  DEV_BOT_ROOT="$(mktemp -d)"
  PROJECT="$(mktemp -d)"
  STUB_BIN="$WORK/bin"
  BUILD_LOG="$WORK/mdctx.log"

  mkdir -p "$STUB_BIN"
  cat > "$STUB_BIN/mdctx" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${BUILD_LOG}"
STUB
  chmod +x "$STUB_BIN/mdctx"

  # The shared index lock lives under XDG_CACHE_HOME — sandbox it, or the test
  # takes the developer's real lock.
  export XDG_CACHE_HOME="$WORK/cache"
  mkdir -p "$XDG_CACHE_HOME/devbot"

  export DEV_BOT_ROOT BUILD_LOG
  export PATH="$STUB_BIN:$PATH"
  export DEVBOT_MEMORY_SEARCH_PROVIDER=mdctx
}

teardown() {
  rm -rf "$WORK" "$DEV_BOT_ROOT" "$PROJECT" 2>/dev/null || true
}

_builds() {
  [[ -f "$BUILD_LOG" ]] && wc -l < "$BUILD_LOG" | tr -d ' ' || echo 0
}

@test "the normal path builds the global index" {
  run bash "$INIT" "$PROJECT"

  assert_success
  assert_equal "$(_builds)" "1"
  assert_equal "$(ls -d "$PROJECT/.agents/memory/active" 2>/dev/null)" "$PROJECT/.agents/memory/active"
}

@test "the deferral flag still scaffolds the vault but skips the shared store" {
  DEV_BOT_DEFER_GLOBAL_MEMORY=1 run bash "$INIT" "$PROJECT"

  assert_success
  assert_equal "$(_builds)" "0"
  assert_equal "$(ls -d "$PROJECT/.agents/memory/active" 2>/dev/null)" "$PROJECT/.agents/memory/active"
}

@test "--global-only builds the shared store without scaffolding a vault" {
  run bash "$INIT" --global-only "$PROJECT"

  assert_success
  assert_equal "$(_builds)" "1"
  run test -d "$PROJECT/.agents/memory"
  assert_failure
}

@test "--global-only skips the build while another process holds the index lock" {
  # A reindex or another init writing the shared index must win: better to
  # leave it for the next start than to write it unlocked.
  python3 - "$XDG_CACHE_HOME/devbot/reindex-memories.lock" <<'HOLD' &
import fcntl, sys, time
f = open(sys.argv[1], "w")
fcntl.flock(f, fcntl.LOCK_EX)
time.sleep(5)
HOLD
  local holder=$!
  sleep 0.5

  DEVBOT_INDEX_LOCK_WAIT=1 run bash "$INIT" --global-only "$PROJECT"
  wait "$holder"

  assert_success
  assert_output --partial "could not take the memory index lock"
  assert_equal "$(_builds)" "0"
}
