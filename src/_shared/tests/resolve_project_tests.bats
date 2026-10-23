#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/resolve_project_tests.bats
# _devbot_resolve_project_for_path maps a path to the registered devbot project
# that contains it (longest path-component prefix in the global config's
# `projects` array). Backs supervisor memory-scoping and per-child config reads.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"

  TMP="$(mktemp -d)"
  # Canonical (symlink-free) base — the helper matches on realpath.
  BASE="$(cd "$TMP" && pwd -P)"
  A="$BASE/a"
  AB="$BASE/ab"
  NESTED="$A/service"
  mkdir -p "$A" "$AB" "$NESTED"

  cat >"$BASE/global.jsonc" <<EOF
{
  // a comment the reader must strip
  "projects": ["$A", "$NESTED"]
}
EOF
}

teardown() {
  rm -rf "$TMP"
}

@test "resolves a child path to its registered project" {
  run bash -c "cd '$A' && touch child.txt"
  run env -u DEV_BOT_ROOT DEV_BOT_GLOBAL_CONFIG="$BASE/global.jsonc" bash -c \
    "source '$PROJECT_ROOT/src/_shared/functions.sh' && _devbot_resolve_project_for_path '$A/child.txt'"
  assert_success
  assert_output "$A"
}

@test "longest registered prefix wins (nested project beats parent)" {
  run env -u DEV_BOT_ROOT DEV_BOT_GLOBAL_CONFIG="$BASE/global.jsonc" bash -c \
    "source '$PROJECT_ROOT/src/_shared/functions.sh' && _devbot_resolve_project_for_path '$NESTED/x.py'"
  assert_success
  assert_output "$NESTED"
}

@test "no false match across a path-component boundary" {
  run env -u DEV_BOT_ROOT DEV_BOT_GLOBAL_CONFIG="$BASE/global.jsonc" bash -c \
    "source '$PROJECT_ROOT/src/_shared/functions.sh' && _devbot_resolve_project_for_path '$AB'"
  assert_success
  assert_output ""
}

@test "prints the default when nothing contains the path" {
  run env -u DEV_BOT_ROOT DEV_BOT_GLOBAL_CONFIG="$BASE/global.jsonc" bash -c \
    "source '$PROJECT_ROOT/src/_shared/functions.sh' && _devbot_resolve_project_for_path '$AB' '$AB'"
  assert_success
  assert_output "$AB"
}

@test "fails open to the default on a missing config" {
  run env -u DEV_BOT_ROOT DEV_BOT_GLOBAL_CONFIG="$BASE/missing.jsonc" bash -c \
    "source '$PROJECT_ROOT/src/_shared/functions.sh' && _devbot_resolve_project_for_path '$A' '$A'"
  assert_success
  assert_output "$A"
}

@test "a child's own commit_memory/workflow win over the supervisor's" {
  mkdir -p "$BASE/sup" "$BASE/child"
  printf '{ "commit_memory": true, "workflow": "worktrees" }\n' >"$BASE/sup/.devbot.project.jsonc"
  printf '{ "commit_memory": false, "workflow": "trunk" }\n' >"$BASE/child/.devbot.project.jsonc"
  printf '{ "commit_memory": true, "workflow": "worktrees" }\n' >"$BASE/global.jsonc"

  run env -u DEV_BOT_ROOT DEV_BOT_GLOBAL_CONFIG="$BASE/global.jsonc" bash -c \
    "source '$PROJECT_ROOT/src/_shared/functions.sh' && _devbot_get_config commit_memory '$BASE/child' && _devbot_get_config workflow '$BASE/child'"
  assert_success
  assert_line --index 0 "false"
  assert_line --index 1 "trunk"
}

@test "the effective workflow is project-first across the retired key" {
  mkdir -p "$BASE/sup" "$BASE/child"
  # The child still carries the retired key; the global config is migrated.
  printf '{ "worktrees": false }\n' >"$BASE/child/.devbot.project.jsonc"
  printf '{ "workflow": "worktrees" }\n' >"$BASE/global.jsonc"

  run env -u DEV_BOT_ROOT DEV_BOT_GLOBAL_CONFIG="$BASE/global.jsonc" bash -c \
    "source '$PROJECT_ROOT/src/_shared/functions.sh' && _devbot_get_workflow '$BASE/child' && echo && _devbot_get_workflow '$BASE/sup'"
  assert_success
  assert_line --index 0 "trunk"
  assert_line --index 1 "worktrees"
}

@test "the effective workflow defaults to worktrees when nothing is set" {
  mkdir -p "$BASE/plain"

  run env -u DEV_BOT_ROOT DEV_BOT_GLOBAL_CONFIG="$BASE/missing.jsonc" bash -c \
    "source '$PROJECT_ROOT/src/_shared/functions.sh' && _devbot_get_workflow '$BASE/plain'"
  assert_success
  assert_output "worktrees"
}
