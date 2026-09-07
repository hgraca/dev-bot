#!/usr/bin/env bats
# =============================================================================
# src/agentic/mdctx/tests/mdctx_tests.bats
# Tests for the mdctx module (MCP-based markdown keyword-index engine, the
# sibling alternative to qmd, selected by memory_search_provider).
#
# The module wraps the mdctx npm package (CLI `mdctx` + MCP server
# `mdctx-mcp`) as the opencode/claudecode memory-search engine. Like its
# sibling codebase-memory it is a plain stdio MCP server on both harnesses —
# mcp.opencode.json EXISTS and plugin.opencode.json MUST NOT. Unlike qmd it has
# no GPU/llama surface (no __GPU_ENABLED__ placeholder) and no docker/up.sh;
# unlike codebase-memory it is per-project (init.sh builds the project index).
#
# The MCP env uses the __DEV_BOT_ROOT__ path-prefix placeholder (resolved at
# registration by bin/init.sh / the harness init), so the manifest asserts the
# template placeholder, not a machine path.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../../.." && pwd)"
}

# ── Module structure ──────────────────────────────────────────────────────────

@test "opencode integration is an MCP entry, not a plugin" {
  local mcp_config="$MODULE_DIR/mcp.opencode.json"
  [ -f "$mcp_config" ]
  run grep -q 'mdctx-mcp' "$mcp_config"
  assert_success
  [ ! -f "$MODULE_DIR/plugin.opencode.json" ]
}

@test "opencode MCP config declares the mdctx key with DEV_BOT_ROOT env" {
  run python3 -c "
import json
d = json.load(open('${MODULE_DIR}/mcp.opencode.json'))
assert 'mdctx' in d, d
m = d['mdctx']
assert m['type'] == 'local', m
assert m['command'] == ['mdctx-mcp'], m
env = m['environment']
assert env['MDCTX_ROOT'] == '__DEV_BOT_ROOT__/storage/global-memories', env
assert env['MDCTX_INDEX'] == '__DEV_BOT_ROOT__/storage/.mdctx/context-index.json', env
print('OPCODE-MCP:OK')
"
  assert_success
  grep -qF 'OPCODE-MCP:OK' <<< "$output" || fail "opencode MCP shape wrong"
}

@test "mdctx MCP env has no GPU placeholder (zero-ML engine)" {
  run grep -c '__GPU_ENABLED__' "$MODULE_DIR/mcp.opencode.json"
  assert_equal "$output" "0"
}

@test "claudecode MCP config registers the mdctx server" {
  local mcp_config="$MODULE_DIR/mcp.claudecode.json"
  [ -f "$mcp_config" ]
  run grep -q 'mdctx-mcp' "$mcp_config"
  assert_success
}

@test "functions.sh sources the shared library (no Ollama models declared)" {
  run grep -c 'LOCAL_MODELS' "$MODULE_DIR/functions.sh"
  assert_equal "$output" "0"
  run grep -q '_shared/functions.sh' "$MODULE_DIR/functions.sh"
  assert_success
}

# ── Lifecycle scripts exist ──────────────────────────────────────────────────

@test "install/update/pre/init scripts exist and are executable" {
  for s in install.sh update.sh pre.sh init.sh; do
    [ -f "$MODULE_DIR/$s" ]
    [ -x "$MODULE_DIR/$s" ]
  done
}

@test "no up.sh / reset.sh — nothing docker or destructive-prune" {
  # No Ollama/docker deps => no up.sh. No per-project reset needed: indexes
  # are just .mdctx JSON files rebuilt by init.sh (unlike qmd's reset.sh,
  # which removes its sqlite collections).
  [ ! -f "$MODULE_DIR/up.sh" ]
  [ ! -f "$MODULE_DIR/reset.sh" ]
}

# ── install.sh / update.sh behaviour (npm guarded by binary presence) ────────
# NOTE: unlike the codebase-memory fixture, the real mdctx binary IS installed
# on dev machines (~/.npm-global/bin), so the sandbox PATH must exclude its
# dir — not just mockbin-first.

_setup_sandbox() {
  SANDBOX="$(mktemp -d)"
  MOCKBIN="${SANDBOX}/mockbin"
  mkdir -p "${MOCKBIN}"
  export NPM_ARGS_FILE="${SANDBOX}/npm.args"
  : > "${NPM_ARGS_FILE}"
  # Dir holding the real mdctx (may be absent on CI) — excluded from PATH.
  local real_mdctx_dir=""
  if command -v mdctx >/dev/null 2>&1; then
    real_mdctx_dir="$(dirname "$(command -v mdctx)")"
  fi
  # Build a PATH with only the dirs that hold python3/node/npm plus mockbin —
  # deliberately excluding any dir that holds a real mdctx, so the test can
  # control whether `command -v mdctx` succeeds.
  local dirs=""
  local bin d
  for bin in python3 node npm; do
    d="$(dirname "$(command -v "$bin")")"
    if [[ -n "${real_mdctx_dir}" && "${d}" == "${real_mdctx_dir}" ]]; then
      continue
    fi
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

_stub_mdctx() {
  cat > "${MOCKBIN}/mdctx" <<'MOCK'
#!/usr/bin/env bash
echo "0.1.0"
MOCK
  chmod +x "${MOCKBIN}/mdctx"
}

# Stub node on PATH reporting an old major (pre.sh must reject < 18).
_stub_old_node() {
  cat > "${MOCKBIN}/node" <<'MOCK'
#!/usr/bin/env bash
echo "v16.20.2"
MOCK
  chmod +x "${MOCKBIN}/node"
}

@test "install.sh: installs mdctx via npm when binary is missing" {
  _setup_sandbox
  _mock_npm

  run bash "$MODULE_DIR/install.sh"

  assert_success
  run cat "${NPM_ARGS_FILE}"
  assert_output --regexp '^install -g mdctx$'
}

@test "install.sh: skips npm install when binary is already present" {
  _setup_sandbox
  _mock_npm
  _stub_mdctx

  run bash "$MODULE_DIR/install.sh"

  assert_success
  [ ! -s "${NPM_ARGS_FILE}" ]
}

@test "update.sh: updates mdctx via npm" {
  _setup_sandbox
  _mock_npm
  _stub_mdctx

  run bash "$MODULE_DIR/update.sh"

  assert_success
  run cat "${NPM_ARGS_FILE}"
  assert_output --regexp '^update -g mdctx$'
}

@test "update.sh: installs via npm when binary is missing (self-healing)" {
  # `npm update -g` on a never-installed package is a silent no-op, and devbot
  # update never runs module install.sh — so update must fall back to install
  # when the binary is absent, or an adopting install (memory_search_provider
  # absent => mdctx default) registers the MCP server with no binary.
  _setup_sandbox
  _mock_npm

  run bash "$MODULE_DIR/update.sh"

  assert_success
  run cat "${NPM_ARGS_FILE}"
  assert_output --regexp '^install -g mdctx$'
}

@test "pre.sh: passes when node and npm are present" {
  _setup_sandbox

  run bash "$MODULE_DIR/pre.sh"

  assert_success
}

@test "pre.sh: fails when node major is below 18" {
  _setup_sandbox
  _stub_old_node

  run bash "$MODULE_DIR/pre.sh"

  assert_failure
  assert_output --partial "Node.js >= 18 is required"
}

# ── init.sh behaviour (per-project index build) ──────────────────────────────

_setup_project() {
  PROJECT_DIR="$(mktemp -d)"
  mkdir -p "${PROJECT_DIR}/.git" "${PROJECT_DIR}/.agents/memory/latent"
  export MDCTX_ARGS_FILE="${PROJECT_DIR}/mdctx.args"
  : > "${MDCTX_ARGS_FILE}"
}

_mock_mdctx_cli() {
  cat > "${MOCKBIN}/mdctx" <<'MOCK'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  echo "0.1.0"
  exit 0
fi
if [[ "${1:-}" == "build" ]]; then
  echo "$@" >> "${MDCTX_ARGS_FILE}"
  echo "Indexed 2 file(s) -> ok"
  exit 0
fi
echo "unknown mdctx invocation: $*" >&2
exit 1
MOCK
  chmod +x "${MOCKBIN}/mdctx"
}

@test "init.sh: builds the project index over latent into <project>/.mdctx" {
  _setup_sandbox
  _mock_mdctx_cli
  _setup_project

  run bash "$MODULE_DIR/init.sh" "${PROJECT_DIR}"

  assert_success
  run cat "${MDCTX_ARGS_FILE}"
  assert_output --regexp '^build .*/.agents/memory/latent -o .*/\.mdctx/context-index\.json$'
  [ -d "${PROJECT_DIR}/.mdctx" ]
  run grep -q '^\.mdctx$' "${PROJECT_DIR}/.git/info/exclude"
  assert_success
}

@test "init.sh: skips (exit 0) when no latent memory directory exists" {
  _setup_sandbox
  _mock_mdctx_cli
  PROJECT_DIR="$(mktemp -d)"
  mkdir -p "${PROJECT_DIR}/.git"

  run bash "$MODULE_DIR/init.sh" "${PROJECT_DIR}"

  assert_success
  [ ! -f "${MDCTX_ARGS_FILE:-${PROJECT_DIR}/mdctx.args}" ]
}

@test "init.sh: fails when mdctx CLI is missing" {
  _setup_sandbox
  _setup_project

  run bash "$MODULE_DIR/init.sh" "${PROJECT_DIR}"

  assert_failure
  assert_output --partial "mdctx CLI not found"
}
