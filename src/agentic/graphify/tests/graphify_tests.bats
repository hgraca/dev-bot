#!/usr/bin/env bats
# =============================================================================
# src/agentic/graphify/tests/graphify_tests.bats
# Tests for the graphify bash entrypoint.
# Tests from the bash entrypoint, covering all options and outputs.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  TOOL="$MODULE_DIR/tools/graphify.sh"
  FIXTURES="$TEST_DIR/fixtures"

  # Stub the graphify CLI so all tests are hermetic. The real CLI
  # builds/rebuilds the knowledge graph (AST extraction + LLM steps), which
  # takes minutes and hangs `make test` — never appropriate in a suite.
  # The stub records its args so tests assert correct delegation.
  FAKE_BIN="$(mktemp -d)"
  cat > "${FAKE_BIN}/graphify" <<'EOF'
#!/usr/bin/env bash
printf 'graphify-args: %s\n' "$*"
EOF
  chmod +x "${FAKE_BIN}/graphify"
  PATH="${FAKE_BIN}:${PATH}"
  export PATH
}

teardown() {
  rm -rf "${FAKE_BIN}"
}

# ── init.sh: .opencode/opencode.json legacy-plugin cleanup (audit-37 §4) ──────
# Every reinit rewrote .opencode/opencode.json via an unconditional
# `jq … > tmp && mv tmp file` even when the graphify plugin entry was already
# absent — byte-identical content, churned mtime on a legacy stub that nothing
# else owns. init.sh must skip the mv when the jq output equals the input.

setup_opencode_project() {
  local dir="$1"
  mkdir -p "${dir}/.opencode" "${dir}/.agents/memory/active" "${dir}/graphify-out"
  printf '{\n  "modules": { "opencode": true, "claudecode": false }\n}\n' \
    > "${dir}/.devbot.project.jsonc"
  printf '{"plugin":[".opencode/plugins/graphify.js"]}\n' \
    > "${dir}/.opencode/opencode.json"
  # Pre-built graph so init.sh skips the background `graphify update .` build.
  printf '{"directed":true,"nodes":[],"links":[]}\n' \
    > "${dir}/graphify-out/graph.json"
}

@test "init.sh: removes the legacy graphify plugin entry from .opencode/opencode.json" {
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  local proj
  proj="$(mktemp -d)"
  setup_opencode_project "${proj}"

  run bash "${MODULE_DIR}/init.sh" "${proj}"

  assert_success
  run jq -r '.plugin[]?' "${proj}/.opencode/opencode.json"
  refute_output --partial "graphify"

  rm -rf "${proj}"
}

@test "init.sh: does not rewrite .opencode/opencode.json when already clean (no mtime churn)" {
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  local proj sentinel
  proj="$(mktemp -d)"
  setup_opencode_project "${proj}"

  # First run cleans the plugin entry (real change, mv expected).
  run bash "${MODULE_DIR}/init.sh" "${proj}"
  assert_success

  # Second run: content must stay byte-identical AND the file must not be
  # touched. A sentinel created before the run must remain newer than the file
  # if the mv is (correctly) skipped.
  cp "${proj}/.opencode/opencode.json" "${proj}/before.json"
  sentinel="$(mktemp)"

  run bash "${MODULE_DIR}/init.sh" "${proj}"
  assert_success

  cmp -s "${proj}/before.json" "${proj}/.opencode/opencode.json"
  assert_success
  run find "${proj}/.opencode/opencode.json" -newer "${sentinel}" -print
  refute_output --partial "opencode.json"

  rm -rf "${proj}" "${sentinel}"
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
  assert_output --partial "FATAL:"
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
  assert_output --partial "FATAL:"
  assert_output --partial "query"
}

@test "query: delegates to graphify CLI" {
  run bash "$TOOL" query "test question"

  assert_success
  assert_output --partial "graphify-args: query test question"
}

@test "query --dfs: passes --dfs flag to traversal" {
  run bash "$TOOL" query "test question" --dfs

  assert_success
  assert_output --partial "graphify-args: query test question --dfs"
}

# ── path (requires graphify CLI) ──────────────────────────────────────────────

@test "path: requires two arguments" {
  run bash "$TOOL" path

  assert_failure
  assert_output --partial "FATAL:"
  assert_output --partial "path"
}

@test "path: requires both source and target" {
  run bash "$TOOL" path "SourceOnly"

  assert_failure
  assert_output --partial "FATAL:"
  assert_output --partial "path"
}

@test "path: delegates to graphify CLI" {
  run bash "$TOOL" path "UserController" "Database"

  # Exact match: a partial match would also pass the old arg-duplication bug
  # (path A B A B), which this test must catch.
  assert_success
  assert_output "graphify-args: path UserController Database"
}

# ── explain (requires graphify CLI) ───────────────────────────────────────────

@test "explain: requires a node name" {
  run bash "$TOOL" explain

  assert_failure
  assert_output --partial "FATAL:"
  assert_output --partial "explain"
}

@test "explain: delegates to graphify CLI" {
  run bash "$TOOL" explain "UserController"

  assert_success
  assert_output --partial "graphify-args: explain UserController"
}

# ── update ─────────────────────────────────────────────────────────────────────

@test "update: delegates to graphify CLI" {
  run bash "$TOOL" update

  # Header printed before delegating; the stub records the rebuild command.
  assert_success
  assert_output --partial "Updating Knowledge Graph"
  assert_output --partial "graphify-args: update ."
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
  run bash -c 'printf "how does auth work" | bash '"$TOOL"' query'

  assert_success
  assert_output --partial "graphify-args: query how does auth work"
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

@test "init.sh: removes the CLI's unnamespaced .claude/skills/graphify copy after claude install" {
  # audit-31 §3: `graphify install --platform claude --project` writes an
  # unnamespaced .claude/skills/graphify/SKILL.md (name: graphify). The
  # claudecode harness flattens dev-bot's own namespaced skill as
  # .claude/skills/devbot:graphify — if the CLI's stale copy survives, both
  # coexist and every reinit re-migrates the old one as a "user skill",
  # producing .bkp churn. init.sh must remove the CLI's copy, mirroring the
  # opencode branch's cleanup of .opencode/skills/graphify.
  setup_init

  # The shared setup() stub only echoes args — replace it with a behavioral
  # stub that mimics the real CLI: `install --platform claude --project`
  # writes the unnamespaced skill dir into the project.
  cat > "${FAKE_BIN}/graphify" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "install" && "$2" == "--platform" && "$3" == "claude" && "$4" == "--project" ]]; then
  mkdir -p .claude/skills/graphify/references
  printf '%s\n' "---" "name: graphify" "---" "" "# Graphify" \
    > .claude/skills/graphify/SKILL.md
  echo "skill installed -> .claude/skills/graphify/SKILL.md"
  exit 0
fi
if [[ "$1" == "install" && "$2" == "--platform" && "$3" == "opencode" && "$4" == "--project" ]]; then
  mkdir -p .opencode/skills/graphify
  printf '%s\n' "---" "name: graphify" "---" "" "# Graphify" \
    > .opencode/skills/graphify/SKILL.md
  echo "skill installed -> .opencode/skills/graphify/SKILL.md"
  exit 0
fi
printf 'graphify-args: %s\n' "$*"
EOF
  chmod +x "${FAKE_BIN}/graphify"

  local tmpdir
  tmpdir="$(mktemp -d)"
  mkdir -p "$tmpdir/src"
  mkdir -p "$tmpdir/.git/hooks"
  printf '# test\n' > "$tmpdir/.gitignore"
  # The claudecode branch only runs when claudecode is enabled — the sandbox
  # needs a project config to override the (claudecode-disabled) global one.
  cat > "$tmpdir/.devbot.project.jsonc" <<'JSON'
{
  "modules": {
    "claudecode": true
  }
}
JSON

  # Sanity: the stub install alone would create the duplicate.
  (cd "$tmpdir" && bash "${FAKE_BIN}/graphify" install --platform claude --project >/dev/null 2>&1)
  assert [ -e "$tmpdir/.claude/skills/graphify/SKILL.md" ]

  STORAGE_ROOT="$tmpdir/graphify-storage" run bash "$INIT_TOOL" "$tmpdir"

  assert_success
  # The CLI's unnamespaced copy must not survive init.
  refute [ -e "$tmpdir/.claude/skills/graphify" ]

  rm -rf "$tmpdir"
}
