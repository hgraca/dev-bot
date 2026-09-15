#!/usr/bin/env bats
# =============================================================================
# src/agentic/signoz/tests/signoz_tests.bats
# Tests for the signoz module (observability MCP server + agent skills).
#
# The MCP server is a machine-wide docker compose gateway (docker-compose.yml)
# from the official image, reached over streamable-http — one container serves
# every harness instance instead of each spawning its own stdio binary. The
# module no longer downloads a per-machine binary or symlinks it into each
# harness dir; only the agent skills are wired per project.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../../.." && pwd)"
}

# ── MCP manifest ─────────────────────────────────────────────────────────────

@test "canonical mcp.json declares signoz as a shared http gateway" {
  run python3 -c "
import json
d = json.load(open('${MODULE_DIR}/mcp.json'))
m = d['mcp']['signoz']
assert m['type'] == 'http', m
assert m['url'] == 'http://127.0.0.1:18502/mcp', m
assert 'command' not in m, m
assert 'env' not in m, m
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
  run grep -q '127.0.0.1:18502:8000' "$compose"
  assert_success
  # Every dev-bot compose file declares the same project name.
  run grep -q 'name: devbot' "$compose"
  assert_success
  # Native HTTP transport — no stdio→http bridge needed for this server.
  run grep -q 'TRANSPORT_MODE: http' "$compose"
  assert_success
}

@test "docker-compose.yml pins the image tag (docker never re-resolves a tag)" {
  run grep -qE 'image: signoz/signoz-mcp-server:v[0-9]+\.[0-9]+\.[0-9]+' "$MODULE_DIR/docker-compose.yml"
  assert_success
}

@test "up.sh waits for the shared gateway" {
  [ -f "${MODULE_DIR}/up.sh" ]
  [ -x "${MODULE_DIR}/up.sh" ]
  run grep -q '18502/mcp' "${MODULE_DIR}/up.sh"
  assert_success
}

# ── No per-machine binary / per-harness symlink ──────────────────────────────

@test "install.sh no longer downloads a per-machine MCP binary" {
  run grep -c '_download_binary\|releases/latest/download' "${MODULE_DIR}/install.sh"
  assert_equal "$output" "0"
}

@test "init.sh no longer symlinks an MCP binary into harness dirs" {
  run grep -c 'signoz-mcp-server' "${MODULE_DIR}/init.sh"
  assert_equal "$output" "0"
}

@test "functions.sh drops the now-unused archive-name helper" {
  run grep -c '_signoz_archive_name' "${MODULE_DIR}/functions.sh"
  assert_equal "$output" "0"
}

# ── Lifecycle scripts ────────────────────────────────────────────────────────

@test "install/update/pre/init/up scripts exist and are executable" {
  for s in install.sh update.sh pre.sh init.sh up.sh; do
    [ -f "${MODULE_DIR}/$s" ]
    [ -x "${MODULE_DIR}/$s" ]
  done
}

@test "functions.sh sources the shared library" {
  run grep -q '_shared/functions.sh' "${MODULE_DIR}/functions.sh"
  assert_success
}