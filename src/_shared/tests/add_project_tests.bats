#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/add_project_tests.bats
# Tests for add_project.py — registers a project in .devbot.global.jsonc.
#
# `devbot init --all -j N` calls this once per worker, so the read-modify-write
# must be serialised and the write atomic:
#   - a lost update silently drops a project from the registry;
#   - a partially written file makes the next `devbot` start fail to parse it,
#     and takes every project with it.
# A no-op must also leave the file byte-identical, or every routine reinit
# would rewrite the registry and lose its comments.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"
  TOOL="${PROJECT_ROOT}/src/_shared/add_project.py"

  WORK="$(mktemp -d)"
  export DEV_BOT_ROOT="$WORK/root"
  mkdir -p "$DEV_BOT_ROOT/storage/locks"

  CFG="$WORK/global.jsonc"
  printf '{\n  "projects": []\n}\n' > "$CFG"
}

teardown() {
  rm -rf "$WORK" 2>/dev/null || true
}

_projects() {
  python3 -c "
import json, sys
print('\n'.join(json.load(open(sys.argv[1]))['projects']))
" "$CFG"
}

@test "registers a project path" {
  mkdir -p "$WORK/proj"

  run python3 "$TOOL" "$CFG" "$WORK/proj"

  assert_success
  assert_output --partial "Registered project: $WORK/proj"
  assert_equal "$(_projects)" "$WORK/proj"
}

@test "an already registered path is a byte-identical no-op" {
  mkdir -p "$WORK/proj"
  python3 "$TOOL" "$CFG" "$WORK/proj" 2>/dev/null
  cp "$CFG" "$WORK/before"

  run python3 "$TOOL" "$CFG" "$WORK/proj"

  assert_success
  assert_output ""
  run cmp -s "$CFG" "$WORK/before"
  assert_success
}

@test "batch registers every path in one invocation, sorted" {
  mkdir -p "$WORK/a" "$WORK/b" "$WORK/c"

  run python3 "$TOOL" "$CFG" "$WORK/c" "$WORK/a" "$WORK/b"

  assert_success
  assert_equal "$(_projects | wc -l | tr -d ' ')" "3"
  assert_equal "$(_projects | head -1)" "$WORK/a"
  assert_equal "$(_projects | tail -1)" "$WORK/c"
}

@test "concurrent invocations never lose an entry" {
  for i in $(seq 1 12); do
    mkdir -p "$WORK/p$i"
  done

  for i in $(seq 1 12); do
    python3 "$TOOL" "$CFG" "$WORK/p$i" 2>/dev/null &
  done
  wait

  run _projects
  assert_success
  assert_equal "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" "12"
}

@test "a successful write leaves no temp file behind" {
  mkdir -p "$WORK/proj"
  python3 "$TOOL" "$CFG" "$WORK/proj" 2>/dev/null

  run find "$WORK" -maxdepth 1 -name '.devbot.global.*.tmp'

  assert_success
  assert_output ""
}

@test "a write that cannot start fails loudly and leaves no temp file" {
  mkdir -p "$WORK/proj"
  # Register once so the lock file exists: the lock is opened for append, which
  # needs no write bit on the directory, and the failure we want is mkstemp.
  python3 "$TOOL" "$CFG" "$WORK/proj" 2>/dev/null
  mkdir -p "$WORK/proj2"
  chmod 500 "$WORK"

  run python3 "$TOOL" "$CFG" "$WORK/proj2"
  chmod 700 "$WORK"

  assert_failure
  assert_output --partial "Failed to write"
  run find "$WORK" -maxdepth 1 -name '.devbot.global.*.tmp'
  assert_output ""
}

@test "the lock follows the config, not the caller's DEV_BOT_ROOT" {
  # DEV_BOT_GLOBAL_CONFIG can point at a registry outside DEV_BOT_ROOT. Two
  # callers with different roots must still serialise on the same config.
  mkdir -p "$WORK/a" "$WORK/b" "$WORK/root-a" "$WORK/root-b"

  DEV_BOT_ROOT="$WORK/root-a" python3 "$TOOL" "$CFG" "$WORK/a" 2>/dev/null &
  local first=$!
  DEV_BOT_ROOT="$WORK/root-b" python3 "$TOOL" "$CFG" "$WORK/b" 2>/dev/null &
  local second=$!
  wait "$first" "$second"

  assert_equal "$(_projects | wc -l | tr -d ' ')" "2"
}

@test "the rewritten config keeps its mode" {
  mkdir -p "$WORK/proj"
  chmod 640 "$CFG"

  python3 "$TOOL" "$CFG" "$WORK/proj" 2>/dev/null

  run stat -c '%a' "$CFG"
  if [[ "$status" -ne 0 ]]; then
    run stat -f '%Lp' "$CFG"   # BSD stat (macOS)
  fi
  assert_output "640"
}
