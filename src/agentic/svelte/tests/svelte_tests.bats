#!/usr/bin/env bats
# =============================================================================
# src/agentic/svelte/tests/svelte_tests.bats
# Tests for the svelte module (Svelte/SvelteKit MCP server + skills).
#
# The MCP server is a machine-wide docker compose gateway (docker-compose.yml)
# reached over streamable-http — one container serves every harness instance
# instead of each spawning its own `npx -y @sveltejs/mcp` stdio process. The
# server is stateless w.r.t. the project (docs are bundled; the autofixer
# receives the code in the tool call), so a single shared container is correct.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../../.." && pwd)"
}

# ── MCP manifest ─────────────────────────────────────────────────────────────

@test "canonical mcp.json declares svelte as a shared http gateway" {
  run python3 -c "
import json
d = json.load(open('${MODULE_DIR}/mcp.json'))
m = d['mcp']['svelte']
assert m['type'] == 'http', m
assert m['url'] == 'http://127.0.0.1:18503/mcp', m
assert 'command' not in m, m
assert 'enabled' not in m, m
print('MCP:OK')
"
  assert_success
  grep -qF 'MCP:OK' <<< "$output" || fail "canonical mcp.json shape wrong"
}

@test "MCP integration is a single canonical mcp.json, not a plugin" {
  [ -f "${MODULE_DIR}/mcp.json" ]
  [ ! -f "${MODULE_DIR}/mcp.opencode.json" ]
  [ ! -f "${MODULE_DIR}/mcp.claudecode.json" ]
  [ ! -f "${MODULE_DIR}/plugin.opencode.json" ]
}

# ── Gateway ──────────────────────────────────────────────────────────────────

@test "docker-compose.yml declares the shared gateway on the 18500+ block" {
  local compose="$MODULE_DIR/docker-compose.yml"
  [ -f "$compose" ]
  # Host-local port mapping only — never exposed off the machine.
  run grep -q '127.0.0.1:18503:18503' "$compose"
  assert_success
  # Every dev-bot compose file declares the same project name.
  run grep -q 'name: devbot' "$compose"
  assert_success
}

@test "Dockerfile pins the stdio server and the bridge" {
  local df="$MODULE_DIR/Dockerfile"
  [ -f "$df" ]
  # The server package is pinned so the image is reproducible.
  run grep -qE 'npm install -g @sveltejs/mcp@[0-9]+\.[0-9]+\.[0-9]+' "$df"
  assert_success
  # mcp-proxy 0.12.0 needs mcp<2 (the SDK moved request_ctx).
  run grep -q 'mcp-proxy==0.12.0' "$df"
  assert_success
  run grep -q '"mcp<2"' "$df"
  assert_success
  # The bridge must bind 0.0.0.0 inside the container for the host mapping.
  run grep -q -- '--host=0.0.0.0' "$df"
  assert_success
}

@test "up.sh waits for the shared gateway" {
  [ -f "${MODULE_DIR}/up.sh" ]
  [ -x "${MODULE_DIR}/up.sh" ]
  run grep -q '18503/mcp' "${MODULE_DIR}/up.sh"
  assert_success
}

# ── No per-instance stdio process ────────────────────────────────────────────

@test "no lifecycle script launches a per-instance npx MCP process" {
  run grep -rn 'npx -y @sveltejs/mcp' "${MODULE_DIR}" --include='*.sh' --include='*.json'
  assert_failure
}

# ── Lifecycle scripts ────────────────────────────────────────────────────────

@test "install/pre/init/up scripts exist and are executable" {
  for s in install.sh pre.sh init.sh up.sh; do
    [ -f "${MODULE_DIR}/$s" ]
    [ -x "${MODULE_DIR}/$s" ]
  done
}

@test "functions.sh sources the shared library" {
  run grep -q '_shared/functions.sh' "${MODULE_DIR}/functions.sh"
  assert_success
}