#!/usr/bin/env bats
# =============================================================================
# src/agentic/mdctx/tests/mdctx_tests.bats
# Tests for the mdctx module (MCP-based markdown keyword-index engine, the
# sibling alternative to qmd, selected by memory_search_provider).
#
# The module wraps the mdctx npm package (CLI `mdctx` + MCP server
# `mdctx-mcp`) as the opencode/claudecode memory-search engine. The MCP server
# is a machine-wide docker compose gateway (docker-compose.yml) reached over
# streamable-http — one container serves every harness instance instead of each
# spawning its own stdio `mdctx-mcp`. A single canonical mcp.json EXISTS (both
# harnesses register from it via the shared translator) and plugin.opencode.json
# MUST NOT. Unlike qmd it has no GPU/llama surface (no __GPU_ENABLED__
# placeholder). The host CLI stays installed — the memory module's tools
# (search-memories, reindex) use it directly.
#
# The gateway URL is host-local (127.0.0.1:18501); the manifest asserts the
# fixed port, not a machine path.
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
  local mcp_config="$MODULE_DIR/mcp.json"
  [ -f "$mcp_config" ]
  # The per-harness manifest pair was consolidated into one canonical file.
  [ ! -f "$MODULE_DIR/mcp.opencode.json" ]
  [ ! -f "$MODULE_DIR/mcp.claudecode.json" ]
  [ ! -f "$MODULE_DIR/plugin.opencode.json" ]
  run grep -q '18501' "$mcp_config"
  assert_success
}

@test "canonical mcp.json declares mdctx as a shared http gateway" {
  # The MCP server no longer runs per-instance: it is a machine-wide docker
  # compose service (docker-compose.yml) reached over streamable-http at /mcp.
  run python3 -c "
import json
d = json.load(open('${MODULE_DIR}/mcp.json'))
m = d['mcp']['mdctx']
assert m['type'] == 'http', m
assert m['url'] == 'http://127.0.0.1:18501/mcp', m
assert 'command' not in m, m
assert 'env' not in m, m
assert 'enabled' not in m, m
print('MCP:OK')
"
  assert_success
  grep -qF 'MCP:OK' <<< "$output" || fail "canonical mcp.json shape wrong"
}

@test "docker-compose.yml declares the shared gateway on the 18500+ block" {
  local compose="$MODULE_DIR/docker-compose.yml"
  [ -f "$compose" ]
  # Host-local port mapping only — never exposed off the machine.
  run grep -q '127.0.0.1:18501:18501' "$compose"
  assert_success
  # Every dev-bot compose file declares the same project name.
  run grep -q 'name: devbot' "$compose"
  assert_success
}

@test "docker-compose.yml runs as the host uid and keeps the corpus read-only" {
  local compose="$MODULE_DIR/docker-compose.yml"
  # The container writes the shared index; running as root would leave a
  # root-owned file that the host `reindex` tool could not rewrite.
  run grep -q 'user: "\${DEV_UID' "$compose"
  assert_success
  # The knowledge base is git-tracked and the server only ever reads it —
  # indexer.js uses readFile/readdir plus a single writeFile to the INDEX path.
  run grep -q 'storage/global-memories:/data/global-memories:ro' "$compose"
  assert_success
  # The index must stay writable: refresh_index (and loadIndex's auto-heal)
  # rewrites it. Asserted as NOT :ro so a stray ':ro' fails this test.
  run grep -q 'storage/.mdctx:/data/.mdctx:ro' "$compose"
  assert_failure
}

@test "Dockerfile pins the bridge and mdctx versions" {
  local df="$MODULE_DIR/Dockerfile"
  [ -f "$df" ]
  # mcp-proxy 0.12.0 needs mcp<2 (the SDK moved request_ctx in 2.x).
  run grep -q 'mcp-proxy==0.12.0' "$df"
  assert_success
  run grep -q 'mcp<2' "$df"
  assert_success
  # mdctx pinned to the host CLI version so the index format matches.
  run grep -q 'mdctx@0.1.0' "$df"
  assert_success
}

@test "Dockerfile passes the environment through the bridge" {
  # mcp-proxy forwards ONLY HOME and PATH to the spawned server unless
  # --pass-environment is given. Without it the child never saw MDCTX_ROOT /
  # MDCTX_INDEX and silently fell back to its CWD (/ in the container) — the
  # MCP handshake still succeeded, so only a real tool call revealed it.
  run grep -q -- '--pass-environment' "${MODULE_DIR}/Dockerfile"
  assert_success
}

@test "mdctx MCP env has no GPU placeholder (zero-ML engine)" {
  run grep -c '__GPU_ENABLED__' "$MODULE_DIR/mcp.json"
  assert_equal "$output" "0"
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

@test "up.sh waits for the shared gateway; no reset.sh" {
  # The MCP server is a docker compose service, so up.sh waits for it to accept
  # MCP requests before the harness starts. No reset.sh: indexes are just
  # .mdctx JSON files rebuilt by init.sh (unlike qmd's sqlite collections).
  [ -f "$MODULE_DIR/up.sh" ]
  [ -x "$MODULE_DIR/up.sh" ]
  [ ! -f "$MODULE_DIR/reset.sh" ]
}

@test "skill has valid frontmatter named devbot:mdctx" {
  local skill="$MODULE_DIR/skills/SKILL.md"
  [ -f "$skill" ]
  run python3 -c "
import json, re, sys
s = open('${skill}').read()
m = re.match(r'^---\n(.*?)\n---', s, re.S)
assert m, 'no YAML frontmatter'
fm = m.group(1)
assert 'name: devbot:mdctx' in fm, fm
assert 'description:' in fm, fm
print('SKILL:OK')
"
  assert_success
  grep -qF 'SKILL:OK' <<< "$output" || fail "skill frontmatter wrong"
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
