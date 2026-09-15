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

# ── Update: the retired per-machine binary must be gone from every script ─────

@test "no signoz script references the retired per-machine binary" {
  # Regression (review F1): the binary removal was swept through install.sh but
  # not update.sh, which kept calling the deleted _signoz_archive_name under
  # `set -e` and died with exit 127 on every `devbot update`.
  run grep -rn '_signoz_archive_name\|signoz-mcp-server' "${MODULE_DIR}" --include='*.sh'
  assert_failure
}

@test "update.sh executes cleanly with a sandboxed DEV_BOT_ROOT" {
  # Executes the script rather than grepping it: the file-shape assertions above
  # are exactly what let a script that exits 127 pass the suite.
  sandbox="$(mktemp -d)"
  mockbin="${sandbox}/mockbin"
  mkdir -p "${mockbin}" "${sandbox}/storage/signoz/skills"

  # Stub npx so the skills step succeeds without touching the network, laying
  # down the .agents/skills layout the real CLI produces.
  cat > "${mockbin}/npx" <<'MOCK'
#!/usr/bin/env bash
mkdir -p .agents/skills/signoz-skill
: > .agents/skills/signoz-skill/SKILL.md
exit 0
MOCK
  chmod +x "${mockbin}/npx"

  # Fail loudly if the retired download path is ever attempted.
  local tool
  for tool in curl wget tar; do
    cat > "${mockbin}/${tool}" <<MOCK
#!/usr/bin/env bash
echo "UNEXPECTED ${tool} invocation" >&2
exit 1
MOCK
    chmod +x "${mockbin}/${tool}"
  done

  run env DEV_BOT_ROOT="${sandbox}" PATH="${mockbin}:${PATH}" \
    bash "${MODULE_DIR}/update.sh"

  assert_success
  refute_output --partial "UNEXPECTED"
  refute_output --partial "command not found"
  # The skills actually landed in the sandboxed storage.
  [ -f "${sandbox}/storage/signoz/skills/signoz-skill/SKILL.md" ]

  rm -rf "${sandbox}"
}

# ── Retired per-machine binary cleanup ──────────────────────────────────────

@test "install.sh removes the retired per-machine binary from an older install" {
  # Review F12: install.sh stopped managing the binary, but an install that
  # predates the shared gateway keeps tens of MB under storage/signoz/bin.
  sandbox="$(mktemp -d)"
  mkdir -p "${sandbox}/storage/signoz/bin" "${sandbox}/storage/signoz/skills/a-skill"
  : > "${sandbox}/storage/signoz/bin/signoz-mcp-server"

  run env DEV_BOT_ROOT="${sandbox}" bash "${MODULE_DIR}/install.sh"

  assert_success
  assert_output --partial "Removed the retired per-machine MCP binary"
  [ ! -e "${sandbox}/storage/signoz/bin" ]
  # The skills survive the cleanup.
  [ -d "${sandbox}/storage/signoz/skills/a-skill" ]
  rm -rf "${sandbox}"
}

@test "install.sh is a no-op cleanup when the retired binary is already gone" {
  sandbox="$(mktemp -d)"
  mkdir -p "${sandbox}/storage/signoz/skills/a-skill"

  run env DEV_BOT_ROOT="${sandbox}" bash "${MODULE_DIR}/install.sh"

  assert_success
  refute_output --partial "Removed the retired"
  rm -rf "${sandbox}"
}

# ── Readiness probe honesty ──────────────────────────────────────────────────

# A curl stub that always succeeds: the MCP `initialize` handshake passes even
# with an empty API key, so a bare probe cannot tell a working gateway from a
# useless one. up.sh must therefore key its verdict off the token as well.
_stub_successful_curl() {
  local mockbin="$1"
  mkdir -p "${mockbin}"
  cat > "${mockbin}/curl" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
  chmod +x "${mockbin}/curl"
}

@test "up.sh reports DEGRADED when SIGNOZ_AUTH_TOKEN is unset" {
  sandbox="$(mktemp -d)"
  _stub_successful_curl "${sandbox}/mockbin"

  run env -u SIGNOZ_AUTH_TOKEN PATH="${sandbox}/mockbin:${PATH}" \
    bash "${MODULE_DIR}/up.sh"

  assert_success
  assert_output --partial "DEGRADED"
  rm -rf "${sandbox}"
}

@test "up.sh reports reachable when SIGNOZ_AUTH_TOKEN is set" {
  sandbox="$(mktemp -d)"
  _stub_successful_curl "${sandbox}/mockbin"

  run env SIGNOZ_AUTH_TOKEN=dummy PATH="${sandbox}/mockbin:${PATH}" \
    bash "${MODULE_DIR}/up.sh"

  assert_success
  assert_output --partial "reachable"
  refute_output --partial "DEGRADED"
  rm -rf "${sandbox}"
}