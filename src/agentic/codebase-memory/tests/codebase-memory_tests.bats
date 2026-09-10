#!/usr/bin/env bats
# =============================================================================
# src/agentic/codebase-memory/tests/codebase-memory_tests.bats
# Tests for the codebase-memory module (MCP-based, no local tool, no plugin).
#
# The module wraps the codebase-memory-mcp native binary (npm package
# codebase-memory-mcp) as the opencode/claudecode codebase engine. Unlike its
# sibling codebase-index (opencode PLUGIN integration), codebase-memory is a
# plain stdio MCP server on both harnesses — hence a single canonical mcp.json
# EXISTS and plugin.opencode.json MUST NOT.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../../.." && pwd)"
}

# ── Module structure ──────────────────────────────────────────────────────────

@test "MCP integration is a single canonical mcp.json, not a plugin" {
  # For opencode codebase-memory is registered as a plain stdio MCP server
  # (upstream ships no opencode plugin). Inverse of codebase-index, which
  # registers as a plugin and deliberately has no MCP registration on opencode.
  local mcp_config="$MODULE_DIR/mcp.json"
  [ -f "$mcp_config" ]
  # The per-harness manifest pair was consolidated into one canonical file.
  [ ! -f "$MODULE_DIR/mcp.opencode.json" ]
  [ ! -f "$MODULE_DIR/mcp.claudecode.json" ]
  [ ! -f "$MODULE_DIR/plugin.opencode.json" ]
  run grep -q 'codebase-memory-mcp' "$mcp_config"
  assert_success
}

@test "canonical mcp.json declares the codebase-memory key as a stdio server" {
  run python3 -c "
import json
d = json.load(open('${MODULE_DIR}/mcp.json'))
m = d['mcp']['codebase-memory']
assert m['type'] == 'stdio', m
assert m['command'][0:2] == ['bash', '-c'], m
assert 'exec codebase-memory-mcp' in m['command'][2], m
assert 'enabled' not in m, m
print('MCP:OK')
"
  assert_success
  grep -qF 'MCP:OK' <<< "$output" || fail "canonical mcp.json shape wrong"
}

@test "functions.sh sources the shared library (no Ollama models declared)" {
  # Unlike codebase-index (LOCAL_MODELS=(nomic-embed-text)), this module
  # bundles its embeddings in the native binary — nothing to pull from Ollama.
  run grep -c 'LOCAL_MODELS' "$MODULE_DIR/functions.sh"
  assert_equal "$output" "0"
  run grep -q '_shared/functions.sh' "$MODULE_DIR/functions.sh"
  assert_success
}

# ── Lifecycle scripts exist ──────────────────────────────────────────────────

@test "install/update/pre scripts exist and are executable" {
  [ -f "$MODULE_DIR/install.sh" ]
  [ -f "$MODULE_DIR/update.sh" ]
  [ -f "$MODULE_DIR/pre.sh" ]
  [ -x "$MODULE_DIR/install.sh" ]
  [ -x "$MODULE_DIR/update.sh" ]
  [ -x "$MODULE_DIR/pre.sh" ]
}

@test "no up.sh / init.sh / reset.sh — nothing docker/Ollama or per-project" {
  # codebase-memory-mcp stores settings account-wide (config set), so no
  # per-project init config copy is needed (codebase-index writes
  # .opencode/codebase-index.json); no Ollama/docker deps means no up.sh.
  [ ! -f "$MODULE_DIR/up.sh" ]
  [ ! -f "$MODULE_DIR/init.sh" ]
  [ ! -f "$MODULE_DIR/reset.sh" ]
}

# ── install.sh behaviour (npm guarded by binary presence) ────────────────────

_setup_sandbox() {
  SANDBOX="$(mktemp -d)"
  MOCKBIN="${SANDBOX}/mockbin"
  mkdir -p "${MOCKBIN}"
  export NPM_ARGS_FILE="${SANDBOX}/npm.args"
  : > "${NPM_ARGS_FILE}"
  # Build a PATH with only the dirs that hold python3/node/npm plus mockbin —
  # deliberately excluding any dir that also holds codebase-memory-mcp, so the
  # test can control whether `command -v codebase-memory-mcp` succeeds.
  local dirs=""
  local bin d
  for bin in python3 node npm; do
    d="$(dirname "$(command -v "$bin")")"
    case ":$dirs:" in
      *":$d:"*) ;;
      *) dirs="${dirs}:${d}" ;;
    esac
  done
  export PATH="${MOCKBIN}:${dirs#:}"
}

_mock_npm() {
  cat > "${MOCKBIN}/npm" <<'MOCK'
#!/usr/bin/env bash
echo "$@" >> "${NPM_ARGS_FILE}"
MOCK
  chmod +x "${MOCKBIN}/npm"
}

_stub_binary() {
  cat > "${MOCKBIN}/codebase-memory-mcp" <<'MOCK'
#!/usr/bin/env bash
echo "0.10.8"
MOCK
  chmod +x "${MOCKBIN}/codebase-memory-mcp"
}

# Stub node on PATH reporting an old major (pre.sh must reject < 18).
_stub_old_node() {
  cat > "${MOCKBIN}/node" <<'MOCK'
#!/usr/bin/env bash
echo "v16.20.2"
MOCK
  chmod +x "${MOCKBIN}/node"
}

@test "install.sh: installs codebase-memory-mcp via npm when binary is missing" {
  _setup_sandbox
  _mock_npm

  run bash "$MODULE_DIR/install.sh"

  assert_success
  run cat "${NPM_ARGS_FILE}"
  assert_output --regexp '^install -g codebase-memory-mcp$'
}

@test "install.sh: skips npm install when binary is already present" {
  _setup_sandbox
  _mock_npm
  _stub_binary

  run bash "$MODULE_DIR/install.sh"

  assert_success
  [ ! -s "${NPM_ARGS_FILE}" ]
}

@test "update.sh: updates codebase-memory-mcp via npm" {
  _setup_sandbox
  _mock_npm
  _stub_binary

  run bash "$MODULE_DIR/update.sh"

  assert_success
  run cat "${NPM_ARGS_FILE}"
  assert_output --regexp '^update -g codebase-memory-mcp$'
}

@test "update.sh: installs via npm when binary is missing (self-healing)" {
  # `npm update -g` on a never-installed package is a silent no-op, and devbot
  # update never runs module install.sh — so update must fall back to install
  # when the binary is absent, or an adopting install registers the MCP server
  # with no binary (review F1).
  _setup_sandbox
  _mock_npm

  run bash "$MODULE_DIR/update.sh"

  assert_success
  run cat "${NPM_ARGS_FILE}"
  assert_output --regexp '^install -g codebase-memory-mcp$'
}

@test "pre.sh: passes when node and npm are present" {
  _setup_sandbox

  run bash "$MODULE_DIR/pre.sh"

  assert_success
}

@test "pre.sh: fails when node major is below 18" {
  # pre.sh documents a Node >= 18 gate (review F5) — an old node must be
  # rejected loudly at prereq time, not surface later at npm install.
  _setup_sandbox
  _stub_old_node

  run bash "$MODULE_DIR/pre.sh"

  assert_failure
  assert_output --partial "Node.js >= 18 is required"
}


# ── Session-start src|app auto-index (operator directive; audit-52/54/55/56) ──

_setup_idx_sandbox() {
  SANDBOX="$(mktemp -d)"
  export DEV_BOT_ROOT="${SANDBOX}"
  MOCKBIN="${SANDBOX}/mockbin"
  mkdir -p "${MOCKBIN}" "${SANDBOX}/src"
  # Pin codebase-memory as the active engine (real reader used by the helper).
  echo '{"codebase_index_provider": "codebase-memory"}' > "${SANDBOX}/.devbot.global.jsonc"
  export CBM_ARGS_FILE="${SANDBOX}/cbm.args"
  : > "${CBM_ARGS_FILE}"
  cat > "${MOCKBIN}/codebase-memory-mcp" <<'MOCK'
#!/usr/bin/env bash
echo "$*" >> "${CBM_ARGS_FILE}"
exit 0
MOCK
  chmod +x "${MOCKBIN}/codebase-memory-mcp"
  # A project rooted inside the sandbox (kept outside the mocked devbot root).
  PROJ="${SANDBOX}/project"
  mkdir -p "${PROJ}"
  export PATH="${MOCKBIN}:$(dirname "$(command -v python3)")"
}

@test "index-project.sh: hooks.json declares the session.created index hook" {
  run python3 -c "
import json
d = json.load(open('${MODULE_DIR}/hooks.json'))
h = d['hooks'][0]
assert h['event'] == 'session.created', h
assert 'index-project.sh' in h['run'][1], h
print('HOOK:OK')
"
  assert_success
  grep -qF 'HOOK:OK' <<< "$output" || fail "hooks.json shape wrong"
  [ -x "$MODULE_DIR/tools/index-project.sh" ]
}

@test "index-project.sh: indexes <project>/src when it exists" {
  _setup_idx_sandbox
  mkdir -p "${PROJ}/src"

  run bash "$MODULE_DIR/tools/index-project.sh" "${PROJ}"
  assert_success

  local i
  for i in $(seq 1 30); do
    [[ -s "${CBM_ARGS_FILE}" ]] && break
    sleep 0.1
  done
  run cat "${CBM_ARGS_FILE}"
  assert_output --regexp '^cli index_repository --repo-path .*/project/src$'

  run cat "${PROJ}/.agents/logs/codebase-memory-index.log"
  assert_output --partial "index-project start"
  assert_output --partial "index-project finished rc=0"
}

@test "index-project.sh: falls back to <project>/app when src is absent" {
  _setup_idx_sandbox
  mkdir -p "${PROJ}/app"

  run bash "$MODULE_DIR/tools/index-project.sh" "${PROJ}"
  assert_success

  local i
  for i in $(seq 1 30); do
    [[ -s "${CBM_ARGS_FILE}" ]] && break
    sleep 0.1
  done
  run cat "${CBM_ARGS_FILE}"
  assert_output --regexp 'index_repository --repo-path .*/project/app'
}

@test "index-project.sh: skips silently when neither src nor app exists" {
  _setup_idx_sandbox
  run bash "$MODULE_DIR/tools/index-project.sh" "${PROJ}"
  assert_success
  [ ! -s "${CBM_ARGS_FILE}" ]
  [ ! -f "${PROJ}/.agents/logs/codebase-memory-index.log" ]
}

@test "index-project.sh: skips when codebase-index is the active engine" {
  _setup_idx_sandbox
  echo '{"codebase_index_provider": "codebase-index"}' > "${SANDBOX}/.devbot.global.jsonc"
  mkdir -p "${PROJ}/src"

  run bash "$MODULE_DIR/tools/index-project.sh" "${PROJ}"
  assert_success
  [ ! -s "${CBM_ARGS_FILE}" ]
}

@test "index-project.sh: skips when the engine binary is missing" {
  _setup_idx_sandbox
  rm -f "${MOCKBIN}/codebase-memory-mcp"
  mkdir -p "${PROJ}/src"

  run bash "$MODULE_DIR/tools/index-project.sh" "${PROJ}"
  assert_success
  [ ! -f "${PROJ}/.agents/logs/codebase-memory-index.log" ]
}
