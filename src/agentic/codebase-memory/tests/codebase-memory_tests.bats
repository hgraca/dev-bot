#!/usr/bin/env bats
# =============================================================================
# src/agentic/codebase-memory/tests/codebase-memory_tests.bats
# Tests for the codebase-memory module (MCP-based, no local tool, no plugin).
#
# The module wraps the codebase-memory-mcp native binary (npm package
# codebase-memory-mcp) as the opencode/claudecode codebase engine. Unlike its
# sibling codebase-index (opencode PLUGIN integration), codebase-memory is a
# plain MCP server registered on both harnesses — hence a single canonical
# mcp.json EXISTS and plugin.opencode.json MUST NOT.
#
# Since the shared-gateway work the canonical manifest declares an http URL: the
# server runs once per machine in a docker compose container (bridged from stdio
# by mcp-proxy) and every harness instance connects to it over
# streamable-http at /mcp.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../../.." && pwd)"
}

teardown() {
  # The session-start index tests run a stub gateway as a background process.
  if [ -n "${STUB_PID:-}" ]; then
    kill "${STUB_PID}" 2>/dev/null || true
    wait "${STUB_PID}" 2>/dev/null || true
  fi
}

# ── Module structure ──────────────────────────────────────────────────────────

@test "MCP integration is a single canonical mcp.json, not a plugin" {
  # codebase-memory is registered as a plain MCP server on both harnesses
  # (upstream ships no opencode plugin). Inverse of codebase-index, which
  # registers as a plugin and deliberately has no MCP registration on opencode.
  # The manifest's transport is http (shared gateway) — asserted in its own test.
  local mcp_config="$MODULE_DIR/mcp.json"
  [ -f "$mcp_config" ]
  # The per-harness manifest pair was consolidated into one canonical file.
  [ ! -f "$MODULE_DIR/mcp.opencode.json" ]
  [ ! -f "$MODULE_DIR/mcp.claudecode.json" ]
  [ ! -f "$MODULE_DIR/plugin.opencode.json" ]
  run grep -q '"codebase-memory"' "$mcp_config"
  assert_success
}

@test "canonical mcp.json declares the codebase-memory key as a shared http gateway" {
  run python3 -c "
import json
d = json.load(open('${MODULE_DIR}/mcp.json'))
m = d['mcp']['codebase-memory']
assert m['type'] == 'http', m
assert m['url'] == 'http://127.0.0.1:18504/mcp', m
assert 'command' not in m, m
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

@test "install/update/pre/init scripts exist and are executable" {
  [ -f "$MODULE_DIR/install.sh" ]
  [ -f "$MODULE_DIR/update.sh" ]
  [ -f "$MODULE_DIR/pre.sh" ]
  [ -f "$MODULE_DIR/init.sh" ]
  [ -x "$MODULE_DIR/install.sh" ]
  [ -x "$MODULE_DIR/update.sh" ]
  [ -x "$MODULE_DIR/pre.sh" ]
  [ -x "$MODULE_DIR/init.sh" ]
}

@test "docker-compose.yml declares the shared gateway on the 18500+ block" {
  local compose="$MODULE_DIR/docker-compose.yml"
  [ -f "$compose" ]
  # Host-local port mapping only — never exposed off the machine.
  run grep -q '127.0.0.1:18504:18504' "$compose"
  assert_success
  # Every dev-bot compose file declares the same project name.
  run grep -q 'name: devbot' "$compose"
  assert_success
}

@test "docker-compose.yml stores the index on a named volume, not a host bind" {
  local compose="$MODULE_DIR/docker-compose.yml"
  # A host bind mount is fatal on Docker Desktop for macOS: a container chmod on
  # it is emulated as `user.containers.override_stat: 0:0:<mode>` whatever uid
  # the container runs as, and the server's private-directory check then reads
  # the directory back as root-owned and refuses to start. A named volume lives
  # on the VM's own filesystem, where chmod is a real syscall.
  run grep -qE '^      - devbot-codebase-memory-store:/srv/cbm$' "$compose"
  assert_success
  run grep -q 'codebase-memory-mcp:\${HOME}/.cache/codebase-memory-mcp' "$compose"
  assert_failure
  run grep -qE '^  devbot-codebase-memory-store:$' "$compose"
  assert_success
  # The repos are still visible at their real host paths, read-only.
  run grep -q 'source: \${CODEBASE_MEMORY_ROOT:-\$HOME}' "$compose"
  assert_success
}

@test "the gateway fixes the store's ownership then drops to DEV_UID" {
  local compose="$MODULE_DIR/docker-compose.yml"
  local df="$MODULE_DIR/Dockerfile"
  local ep="$MODULE_DIR/entrypoint.sh"
  # The volume's owner cannot be baked into the image (the host uid is only
  # known at run time) and the server validates that it owns the store — so the
  # container starts as root only long enough to chown it, then drops.
  [ -f "$ep" ]
  run grep -q 'chown' "$ep"
  assert_success
  run grep -q 'setpriv' "$ep"
  assert_success
  run grep -q 'DEV_UID' "$ep"
  assert_success
  run grep -q 'ENTRYPOINT' "$df"
  assert_success
  # ... and the uid reaches it as env, not via `user:` (which would remove the
  # privilege the chown needs).
  run grep -q 'DEV_UID' "$compose"
  assert_success
  run grep -q 'user: "\${DEV_UID' "$compose"
  assert_failure
}

@test "Dockerfile pins the server and the bridge" {
  local df="$MODULE_DIR/Dockerfile"
  [ -f "$df" ]
  run grep -qE 'npm install -g codebase-memory-mcp@[0-9]+\.[0-9]+\.[0-9]+' "$df"
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

@test "Dockerfile passes the environment through the bridge" {
  # mcp-proxy forwards ONLY HOME and PATH unless --pass-environment is given.
  # This server needs HOME (its cache/store lives under it), so make the
  # forwarding explicit rather than relying on the proxy's incidental pass.
  run grep -q -- '--pass-environment' "${MODULE_DIR}/Dockerfile"
  assert_success
}

@test "up.sh waits for the shared gateway" {
  [ -f "${MODULE_DIR}/up.sh" ]
  [ -x "${MODULE_DIR}/up.sh" ]
  run grep -q '18504/mcp' "${MODULE_DIR}/up.sh"
  assert_success
}

@test "no lifecycle script launches a per-instance stdio MCP process" {
  # The host session-start hook still runs `codebase-memory-mcp cli ...` (a
  # one-shot index, not the MCP server) — only the server launch must be gone.
  run grep -rn 'exec codebase-memory-mcp' "${MODULE_DIR}" --include='*.sh' --include='*.json'
  assert_failure
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

# ── init.sh behaviour (dependency self-heal at reinit) ───────────────────────
# devbot update never runs module install.sh, and devbot init runs init.sh —
# so without an init.sh an install that adopts codebase-memory via update+reinit
# registers the MCP server with no binary (review F1). init.sh delegates to the
# idempotent install.sh when the binary is absent.

@test "init.sh: installs codebase-memory-mcp when the binary is missing" {
  _setup_sandbox
  _mock_npm

  run bash "$MODULE_DIR/init.sh"

  assert_success
  run cat "${NPM_ARGS_FILE}"
  assert_output --regexp '^install -g codebase-memory-mcp$'
}

@test "init.sh: skips install when the binary is already present" {
  _setup_sandbox
  _mock_npm
  _stub_binary

  run bash "$MODULE_DIR/init.sh"

  assert_success
  [ ! -s "${NPM_ARGS_FILE}" ]
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
  mkdir -p "${SANDBOX}/src"
  # Pin codebase-memory as the active engine (real reader used by the helper).
  echo '{"codebase_index_provider": "codebase-memory"}' > "${SANDBOX}/.devbot.global.jsonc"
  export CBM_CALLS_FILE="${SANDBOX}/cbm.calls"
  : > "${CBM_CALLS_FILE}"
  # A project rooted inside the sandbox (kept outside the mocked devbot root).
  PROJ="${SANDBOX}/project"
  mkdir -p "${PROJ}"
  # Only python3's own directory: the hook's reachability guard is a bash
  # /dev/tcp connect and needs no PATH entry, so nothing else has to be present
  # for the hook to run — this is what the index helper is invoked with.
  export PATH="$(dirname "$(command -v python3)")"

  # Stub gateway. The hook indexes through the shared gateway over MCP now, not
  # a host binary, so exercise the real streamable-http conversation: the
  # initialize handshake hands out a session id, and every tools/call is
  # recorded so the test can assert the repo_path that was asked for.
  STUB_PORT=$(( 20000 + RANDOM % 20000 ))
  cat > "${SANDBOX}/stub-gateway.py" <<'STUB'
import http.server
import json
import sys

PORT, CALLS, MODE = int(sys.argv[1]), sys.argv[2], sys.argv[3]


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("content-length", 0) or 0)
        body = json.loads(self.rfile.read(length) or b"{}")
        method = body.get("method")
        if method == "initialize":
            try:
                flag = open(MODE).read().strip()
            except OSError:
                flag = ""
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            if flag != "nosession":
                self.send_header("Mcp-Session-Id", "stub-session")
            self.end_headers()
            self.wfile.write(b'{"jsonrpc":"2.0","id":1,"result":{}}')
        elif method == "tools/call":
            # Streamable HTTP requires the id handed out by `initialize` on
            # every later request. Enforcing it here is what makes the positive
            # tests actually prove the echo — otherwise a bare call is accepted
            # and a regression that dropped the header would stay green.
            if self.headers.get("Mcp-Session-Id") != "stub-session":
                self.send_response(400)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(b'{"error":"Missing session ID"}')
                return
            with open(CALLS, "a") as fh:
                fh.write(json.dumps(body.get("params", {})) + "\n")
            try:
                flag = open(MODE).read().strip()
            except OSError:
                flag = ""
            payload = (
                b'{"jsonrpc":"2.0","id":2,"result":{"isError":true,"content":[]}}'
                if flag == "error"
                else b'{"jsonrpc":"2.0","id":2,"result":{"content":[]}}'
            )
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(payload)
        else:
            self.send_response(202)
            self.end_headers()

    def log_message(self, *args):
        pass


http.server.HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
STUB
  : > "${SANDBOX}/stub-mode"
  python3 "${SANDBOX}/stub-gateway.py" "${STUB_PORT}" "${CBM_CALLS_FILE}" "${SANDBOX}/stub-mode" &
  STUB_PID=$!
  export CODEBASE_MEMORY_MCP_URL="http://127.0.0.1:${STUB_PORT}/mcp"

  local i
  for i in $(seq 1 50); do
    (exec 3<>"/dev/tcp/127.0.0.1/${STUB_PORT}") 2>/dev/null && return 0
    sleep 0.1
  done
  return 0
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

@test "index-project.sh: indexes <project>/src through the gateway" {
  _setup_idx_sandbox
  mkdir -p "${PROJ}/src"

  run bash "$MODULE_DIR/tools/index-project.sh" "${PROJ}"
  assert_success

  local i
  for i in $(seq 1 50); do
    [[ -s "${CBM_CALLS_FILE}" ]] && break
    sleep 0.1
  done
  run cat "${CBM_CALLS_FILE}"
  assert_output --partial '"name": "index_repository"'
  assert_output --partial "${PROJ}/src"

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
  for i in $(seq 1 50); do
    [[ -s "${CBM_CALLS_FILE}" ]] && break
    sleep 0.1
  done
  run cat "${CBM_CALLS_FILE}"
  assert_output --partial '"name": "index_repository"'
  assert_output --partial "${PROJ}/app"
}

@test "index-project.sh: logs a non-zero rc when the index fails" {
  # A JSON-RPC success can still carry a failed tool result. The hook logs the
  # helper's return code, so a failed index must not read as rc=0.
  _setup_idx_sandbox
  mkdir -p "${PROJ}/src"
  echo error > "${SANDBOX}/stub-mode"

  run bash "$MODULE_DIR/tools/index-project.sh" "${PROJ}"
  assert_success

  local i
  for i in $(seq 1 50); do
    grep -q 'index-project finished' "${PROJ}/.agents/logs/codebase-memory-index.log" 2>/dev/null && break
    sleep 0.1
  done
  run cat "${PROJ}/.agents/logs/codebase-memory-index.log"
  assert_output --partial "index-project finished rc=1"
}

@test "index-project.sh: fails when the gateway never hands out a session id" {
  # The stubbed gateway enforces the session header on tools/call, so a call
  # made without one is rejected. Drives the same path a gateway that did not
  # return a session id would.
  _setup_idx_sandbox
  mkdir -p "${PROJ}/src"
  echo nosession > "${SANDBOX}/stub-mode"

  run bash "$MODULE_DIR/tools/index-project.sh" "${PROJ}"
  assert_success

  local i
  for i in $(seq 1 50); do
    grep -q 'index-project finished' "${PROJ}/.agents/logs/codebase-memory-index.log" 2>/dev/null && break
    sleep 0.1
  done
  run cat "${PROJ}/.agents/logs/codebase-memory-index.log"
  assert_output --partial "index-project finished rc=1"
  [ ! -s "${CBM_CALLS_FILE}" ]
}

@test "index-project.sh: skips silently when neither src nor app exists" {
  _setup_idx_sandbox
  run bash "$MODULE_DIR/tools/index-project.sh" "${PROJ}"
  assert_success
  [ ! -s "${CBM_CALLS_FILE}" ]
  [ ! -f "${PROJ}/.agents/logs/codebase-memory-index.log" ]
}

@test "index-project.sh: skips when codebase-index is the active engine" {
  _setup_idx_sandbox
  echo '{"codebase_index_provider": "codebase-index"}' > "${SANDBOX}/.devbot.global.jsonc"
  mkdir -p "${PROJ}/src"

  run bash "$MODULE_DIR/tools/index-project.sh" "${PROJ}"
  assert_success
  [ ! -s "${CBM_CALLS_FILE}" ]
}

@test "index-project.sh: skips when the gateway is not reachable" {
  _setup_idx_sandbox
  mkdir -p "${PROJ}/src"
  # Nothing listens here. A bare harness boot without `devbot up` must be a
  # silent no-op — not a log line written on every session start.
  export CODEBASE_MEMORY_MCP_URL="http://127.0.0.1:1/mcp"

  run bash "$MODULE_DIR/tools/index-project.sh" "${PROJ}"
  assert_success
  [ ! -s "${CBM_CALLS_FILE}" ]
  [ ! -f "${PROJ}/.agents/logs/codebase-memory-index.log" ]
}
