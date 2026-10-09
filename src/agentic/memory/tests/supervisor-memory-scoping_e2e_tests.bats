#!/usr/bin/env bats
# =============================================================================
# src/agentic/memory/tests/supervisor-memory-scoping_e2e_tests.bats
# End-to-end: a supervisor session's memory read set is resolved from the
# touched files — child project + supervisor + global store, never an
# untouched sibling; a session inside a child stays child + global.
# Runs against a real mdctx index (skipped when mdctx is absent).
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  TOOL="$MODULE_DIR/tools/search-memories/search-memories.mcp.sh"
  REPO_ROOT="$(cd "$MODULE_DIR/../../.." && pwd)"

  command -v mdctx &>/dev/null || skip "mdctx CLI not installed"

  WORK="$(mktemp -d)"
  DEVROOT="$WORK/devbot-root"
  SUP="$WORK/sup"
  CHILD="$WORK/child-a"
  OTHER="$WORK/child-b"

  # Sandbox devbot root: the shared resolvers + an isolated global store.
  mkdir -p "$DEVROOT/src/_shared" "$DEVROOT/storage/global-memories" "$DEVROOT/storage/.mdctx"
  ln -s "$REPO_ROOT/src/_shared/read_jsonc.py" "$DEVROOT/src/_shared/read_jsonc.py"
  ln -s "$REPO_ROOT/src/_shared/resolve_project.py" "$DEVROOT/src/_shared/resolve_project.py"

  for p in "$SUP" "$CHILD" "$OTHER"; do
    mkdir -p "$p/.agents/memory/latent" "$p/.mdctx"
  done

  printf '{ "project_name": "sup", "supervisor": true, "devbot_dir": ".agents" }\n' >"$SUP/.devbot.project.jsonc"
  printf '{ "project_name": "child-a", "devbot_dir": ".agents" }\n' >"$CHILD/.devbot.project.jsonc"
  printf '{ "project_name": "child-b", "devbot_dir": ".agents" }\n' >"$OTHER/.devbot.project.jsonc"
  printf '{ "projects": ["%s"], "devbot_dir": ".agents" }\n' "$CHILD" >"$DEVROOT/.devbot.global.jsonc"

  printf '# Child A\n\nThe alphaspecial marker.\n' >"$CHILD/.agents/memory/latent/a.md"
  printf '# Child B\n\nThe betaspecial marker.\n' >"$OTHER/.agents/memory/latent/b.md"
  printf '# Supervisor\n\nThe sierraspecial marker.\n' >"$SUP/.agents/memory/latent/s.md"
  printf '# Global\n\nThe globalspecial marker.\n' >"$DEVROOT/storage/global-memories/g.md"

  mdctx build "$SUP/.agents/memory/latent" -o "$SUP/.mdctx/context-index.json" >/dev/null 2>&1
  mdctx build "$CHILD/.agents/memory/latent" -o "$CHILD/.mdctx/context-index.json" >/dev/null 2>&1
  mdctx build "$OTHER/.agents/memory/latent" -o "$OTHER/.mdctx/context-index.json" >/dev/null 2>&1
  mdctx build "$DEVROOT/storage/global-memories" -o "$DEVROOT/storage/.mdctx/context-index.json" >/dev/null 2>&1
}

teardown() {
  rm -rf "$WORK"
}

_run_search() {
  # $1 = cwd, rest = tool args
  local cwd="$1"
  shift
  cd "$cwd"
  run env \
    SEARCH_MEMORIES_DEV_BOT_ROOT="$DEVROOT" \
    SEARCH_MEMORIES_PROVIDER=mdctx \
    SEARCH_MEMORIES_SKIP_INDEX_CHECK=1 \
    bash "$TOOL" "$@"
  cd "$WORK"
}

@test "supervisor + focus returns the touched child, the supervisor and global" {
  _run_search "$SUP" --query alphaspecial --query sierraspecial --query globalspecial --focus "$CHILD/.agents/memory/latent/a.md"
  assert_success
  assert_output --partial "alphaspecial"
  assert_output --partial "sierraspecial"
  assert_output --partial "globalspecial"
  refute_output --partial "betaspecial"
}

@test "supervisor with no focus returns only the supervisor and global" {
  _run_search "$SUP" --query alphaspecial --query betaspecial --query sierraspecial --query globalspecial
  assert_success
  assert_output --partial "sierraspecial"
  assert_output --partial "globalspecial"
  refute_output --partial "alphaspecial"
  refute_output --partial "betaspecial"
}

@test "a session inside a child returns the child and global, never the supervisor" {
  _run_search "$CHILD" --query alphaspecial --query sierraspecial --query globalspecial
  assert_success
  assert_output --partial "alphaspecial"
  assert_output --partial "globalspecial"
  refute_output --partial "sierraspecial"
}
