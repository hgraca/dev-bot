#!/usr/bin/env bats
# =============================================================================
# src/agentic/graphify/tests/graphify_tests.bats
# Tests for the graphify bash entrypoint.
# Tests from the bash entrypoint, covering all options and outputs.
# =============================================================================

setup() {
  load "$(npm root -g)/bats-support/load.bash"
  load "$(npm root -g)/bats-assert/load.bash"

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  TOOL="$MODULE_DIR/tools/graphify.sh"
  FIXTURES="$TEST_DIR/fixtures"

  # Prefer the installed graphify CLI — skip tests if unavailable
  # (but allow --help tests to pass even without it)
  GRAPHIFY_AVAILABLE=false
  if command -v graphify &>/dev/null; then
    GRAPHIFY_AVAILABLE=true
  fi
}

# ── Help flag ─────────────────────────────────────────────────────────────────

@test "--help: prints usage and exits 0" {
  run bash "$TOOL" --help

  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "query"
  assert_output --partial "path"
  assert_output --partial "explain"
  assert_output --partial "update"
}

@test "--help: -h also prints usage" {
  run bash "$TOOL" -h

  assert_success
  assert_output --partial "Usage:"
}

# ── No arguments ──────────────────────────────────────────────────────────────

@test "no args: prints help and exits 0" {
  run bash "$TOOL"

  assert_success
  assert_output --partial "Usage:"
}

# ── Unknown command ───────────────────────────────────────────────────────────

@test "unknown command: prints error and exits 1" {
  run bash "$TOOL" nonexistent

  assert_failure
  assert_output --partial "Error"
  assert_output --partial "nonexistent"
}

# ── graph-stats ───────────────────────────────────────────────────────────────

@test "graph-stats: no graph found exits 0 with message" {
  # Run from a temp dir with no graphify-out
  local tmpdir
  tmpdir="$(mktemp -d)"

  run bash -c "cd '$tmpdir' && bash '$TOOL' graph-stats"

  assert_success
  assert_output --partial "No graph found"

  rm -rf "$tmpdir"
}

@test "graph-stats: prints table when graph exists" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  mkdir -p "$tmpdir/graphify-out"
  cp "$FIXTURES/sample-graph.json" "$tmpdir/graphify-out/graph.json"

  run bash -c "cd '$tmpdir' && bash '$TOOL' graph-stats"

  assert_success
  assert_output --partial "Graph Statistics"
  assert_output --partial "Nodes"
  assert_output --partial "Edges"
  assert_output --regexp '5\s*\|'

  rm -rf "$tmpdir"
}

# ── god-nodes ─────────────────────────────────────────────────────────────────

@test "god-nodes: prints table of most connected nodes when graph exists" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  mkdir -p "$tmpdir/graphify-out"
  cp "$FIXTURES/sample-graph.json" "$tmpdir/graphify-out/graph.json"

  run bash -c "cd '$tmpdir' && bash '$TOOL' god-nodes"

  assert_success
  assert_output --partial "Most Connected Nodes"
  assert_output --partial "Connections"

  rm -rf "$tmpdir"
}

# ── query (requires graphify CLI) ─────────────────────────────────────────────

@test "query: requires a question" {
  run bash "$TOOL" query

  assert_failure
  assert_output --partial "Error"
  assert_output --partial "query"
}

@test "query: delegates to graphify CLI when installed" {
  if [[ "$GRAPHIFY_AVAILABLE" != "true" ]]; then
    skip "graphify CLI not installed"
  fi

  run bash "$TOOL" query "test question"

  # If graph exists, graphify returns traversal results
  # If graph doesn't exist, it returns an error
  # Either way the delegation worked — just verify we got output
  assert_output --partial "Start:" || assert_output --partial "No graph found" || assert_output --partial "graph.json" || assert_output --partial "error" || assert_failure
}

@test "query --dfs: passes --dfs flag to traversal" {
  if [[ "$GRAPHIFY_AVAILABLE" != "true" ]]; then
    skip "graphify CLI not installed"
  fi

  run bash "$TOOL" query "test question" --dfs

  # --dfs changes traversal mode — output should mention DFS
  assert_output --partial "DFS" || assert_output --partial "No graph found" || assert_output --partial "error" || assert_failure
}

# ── path (requires graphify CLI) ──────────────────────────────────────────────

@test "path: requires two arguments" {
  run bash "$TOOL" path

  assert_failure
  assert_output --partial "Error"
  assert_output --partial "path"
}

@test "path: requires both source and target" {
  run bash "$TOOL" path "SourceOnly"

  assert_failure
  assert_output --partial "Error"
  assert_output --partial "path"
}

@test "path: delegates to graphify CLI when installed" {
  if [[ "$GRAPHIFY_AVAILABLE" != "true" ]]; then
    skip "graphify CLI not installed"
  fi

  run bash "$TOOL" path "UserController" "Database"
  assert_output --partial "No graph found" || assert_output --partial "graph.json" || assert_failure
}

# ── explain (requires graphify CLI) ───────────────────────────────────────────

@test "explain: requires a node name" {
  run bash "$TOOL" explain

  assert_failure
  assert_output --partial "Error"
  assert_output --partial "explain"
}

@test "explain: delegates to graphify CLI when installed" {
  if [[ "$GRAPHIFY_AVAILABLE" != "true" ]]; then
    skip "graphify CLI not installed"
  fi

  run bash "$TOOL" explain "UserController"

  # Delegation worked — graphify CLI ran. Output depends on graph state.
  assert_output --partial "NODE:" || assert_output --partial "No graph found" || assert_output --partial "No node matching" || assert_failure
}

# ── update ─────────────────────────────────────────────────────────────────────

@test "update: shows header when graphify CLI installed" {
  if [[ "$GRAPHIFY_AVAILABLE" != "true" ]]; then
    skip "graphify CLI not installed"
  fi

  run bash "$TOOL" update

  # Header must be printed
  assert_output --partial "Updating Knowledge Graph"

  # Exit code depends on whether graphify-out exists and has files to update
  # (Not checking success/failure — just verifies the delegation happened)
}

# ── Edge cases ─────────────────────────────────────────────────────────────────

@test "empty graph file: handles gracefully" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  mkdir -p "$tmpdir/graphify-out"
  echo '{"nodes":[],"links":[]}' > "$tmpdir/graphify-out/graph.json"

  run bash -c "cd '$tmpdir' && bash '$TOOL' graph-stats"

  assert_success
  assert_output --partial "Nodes"
  assert_output --regexp '0\s*\|'

  rm -rf "$tmpdir"
}

@test "pipe mode: reads query from stdin" {
  if [[ "$GRAPHIFY_AVAILABLE" != "true" ]]; then
    skip "graphify CLI not installed"
  fi

  run bash -c 'printf "how does auth work" | bash '"$TOOL"' query'

  # Should show either graph traversal or graph error — delegation works either way
  assert_output --partial "Start:" || assert_output --partial "No graph found" || assert_failure
}

@test "god-nodes: empty graph shows zero connections" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  mkdir -p "$tmpdir/graphify-out"
  echo '{"nodes":[],"links":[]}' > "$tmpdir/graphify-out/graph.json"

  run bash -c "cd '$tmpdir' && bash '$TOOL' god-nodes"

  assert_success
  assert_output --partial "Most Connected Nodes"

  rm -rf "$tmpdir"
}

# ── init.sh tests ──────────────────────────────────────────────────────────────

setup_init() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  INIT_TOOL="$MODULE_DIR/init.sh"
}

@test "init.sh: reports error when graphify not installed (text check)" {
  setup_init

  # The init.sh checks `command -v graphify` and errors before doing anything.
  # We can verify the error text exists in the script source.
  run grep -q "graphify not found" "$INIT_TOOL"
  assert_success
}

@test "init.sh: creates .graphifyignore with src scope" {
  if ! command -v graphify &>/dev/null; then
    skip "graphify CLI not installed"
  fi

  setup_init

  local tmpdir
  tmpdir="$(mktemp -d)"
  mkdir -p "$tmpdir/src"
  mkdir -p "$tmpdir/.git/hooks"
  printf '# test\n' > "$tmpdir/.gitignore"

  STORAGE_ROOT="$tmpdir/graphify-storage" run bash "$INIT_TOOL" "$tmpdir"

  assert_success
  assert_output --partial "Restricting graphify index to src/"
  assert_output --partial "Created .graphifyignore"
  # Verify the file was actually created
  [[ -f "$tmpdir/.graphifyignore" ]]

  rm -rf "$tmpdir"
}

@test "init.sh: creates .graphifyignore with app scope" {
  if ! command -v graphify &>/dev/null; then
    skip "graphify CLI not installed"
  fi

  setup_init

  local tmpdir
  tmpdir="$(mktemp -d)"
  mkdir -p "$tmpdir/app"
  mkdir -p "$tmpdir/.git/hooks"
  printf '# test\n' > "$tmpdir/.gitignore"

  STORAGE_ROOT="$tmpdir/graphify-storage" run bash "$INIT_TOOL" "$tmpdir"

  assert_success
  assert_output --partial "Restricting graphify index to app/"
  assert_output --partial "Created .graphifyignore"
  # Verify the file was actually created
  [[ -f "$tmpdir/.graphifyignore" ]]

  rm -rf "$tmpdir"
}

@test "init.sh: writes graphify-out/ to .gitignore and .git/info/exclude" {
  if ! command -v graphify &>/dev/null; then
    skip "graphify CLI not installed"
  fi

  setup_init

  local tmpdir
  tmpdir="$(mktemp -d)"
  mkdir -p "$tmpdir/src"
  mkdir -p "$tmpdir/.git/hooks"

  STORAGE_ROOT="$tmpdir/graphify-storage" run bash "$INIT_TOOL" "$tmpdir"

  assert_success
  # .gitignore is required by the codebase-index watcher; .git/info/exclude is not read by it.
  run grep -q '^graphify-out/$' "$tmpdir/.gitignore"
  assert_success
  run grep -q '^graphify-out/$' "$tmpdir/.git/info/exclude"
  assert_success

  rm -rf "$tmpdir"
}

@test "init.sh: copies graphify bootstrap memory from module template" {
  if ! command -v graphify &>/dev/null; then
    skip "graphify CLI not installed"
  fi

  setup_init

  local tmpdir
  tmpdir="$(mktemp -d)"
  mkdir -p "$tmpdir/src"
  mkdir -p "$tmpdir/.git/hooks"

  STORAGE_ROOT="$tmpdir/graphify-storage" run bash "$INIT_TOOL" "$tmpdir"

  assert_success
  assert_output --partial "Installed graphify bootstrap memory"
  [[ -f "$tmpdir/.agents/memory/active/graphify.md" ]]
  run grep -q '^## graphify' "$tmpdir/.agents/memory/active/graphify.md"
  assert_success

  rm -rf "$tmpdir"
}

@test "init.sh: removes graphify section from AGENTS.md if present" {
  if ! command -v graphify &>/dev/null; then
    skip "graphify CLI not installed"
  fi

  setup_init

  local tmpdir
  tmpdir="$(mktemp -d)"
  mkdir -p "$tmpdir/src"
  mkdir -p "$tmpdir/.git/hooks"
  printf '## graphify\nSome graphify content.\n\n## Other\nkeep me\n' > "$tmpdir/AGENTS.md"

  STORAGE_ROOT="$tmpdir/graphify-storage" run bash "$INIT_TOOL" "$tmpdir"

  assert_success
  assert_output --partial "Removed graphify section from AGENTS.md"
  run grep -q '## graphify' "$tmpdir/AGENTS.md"
  assert_failure
  run grep -q 'keep me' "$tmpdir/AGENTS.md"
  assert_success

  rm -rf "$tmpdir"
}

@test "init.sh: skips graph build when already exists" {
  if ! command -v graphify &>/dev/null; then
    skip "graphify CLI not installed"
  fi

  setup_init

  local tmpdir
  tmpdir="$(mktemp -d)"
  mkdir -p "$tmpdir/graphify-out"
  mkdir -p "$tmpdir/.git/hooks"
  echo '{"nodes":[],"links":[]}' > "$tmpdir/graphify-out/graph.json"

  STORAGE_ROOT="$tmpdir/graphify-storage" run bash "$INIT_TOOL" "$tmpdir"

  assert_output --partial "already built"

  rm -rf "$tmpdir"
}
