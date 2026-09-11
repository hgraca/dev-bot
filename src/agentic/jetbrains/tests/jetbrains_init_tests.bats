#!/usr/bin/env bats
# =============================================================================
# src/agentic/jetbrains/tests/jetbrains_init_tests.bats
# Tests for the jetbrains init.sh OpenCode manifest.
#
# The IJ_MCP_SERVER_PROJECT_PATH header must be emitted as a portable
# {env:VAR} token rather than a baked absolute path, so the same manifest works
# across machines and projects:
#   - default            -> {env:PWD}
#   - JETBRAINS_PROJECT_PATH set -> {env:JETBRAINS_PROJECT_PATH}
#
# Hermetic: pgrep is shimmed to fail, so init.sh always takes the host-probe
# branch against our fake SSE endpoint regardless of any real IDE running.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  INIT_TOOL="${MODULE_DIR}/init.sh"

  PROJECT="$(mktemp -d)"
  printf '{\n  "modules": { "opencode": true }\n}\n' > "${PROJECT}/.devbot.project.jsonc"

  # Shim pgrep so IDE auto-detection always fails and init.sh probes
  # JETBRAINS_PORT (our fake endpoint) instead of a real IDE.
  SHIM_DIR="$(mktemp -d)"
  printf '#!/usr/bin/env bash\nexit 1\n' > "${SHIM_DIR}/pgrep"
  chmod +x "${SHIM_DIR}/pgrep"

  # Fake MCP SSE endpoint. It binds :0 and writes the chosen port to a file so
  # there is no free-port race; init.sh accepts any reply carrying
  # text/event-stream.
  PORT_FILE="${SHIM_DIR}/port"
  python3 - "${PORT_FILE}" <<'PY' &
import socket, sys

srv = socket.socket()
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", 0))
srv.listen(16)
with open(sys.argv[1], "w") as fh:
    fh.write(str(srv.getsockname()[1]))

while True:
    try:
        conn, _ = srv.accept()
    except OSError:
        break
    try:
        conn.recv(4096)
        conn.sendall(b"HTTP/1.0 200 OK\r\nContent-Type: text/event-stream\r\n\r\n")
    except OSError:
        pass
    finally:
        conn.close()
PY
  SERVER_PID=$!

  local i
  for ((i = 0; i < 200; i++)); do
    [[ -s "${PORT_FILE}" ]] && break
    sleep 0.05
  done
  [[ -s "${PORT_FILE}" ]] || fail "fake SSE endpoint failed to start"
  FAKE_PORT="$(cat "${PORT_FILE}")"
  _await_endpoint "${FAKE_PORT}" || fail "fake SSE endpoint not accepting connections"
}

teardown() {
  kill "${SERVER_PID}" 2>/dev/null || true
  wait "${SERVER_PID}" 2>/dev/null || true
  rm -rf "${PROJECT}" "${SHIM_DIR}"
}

_await_endpoint() {
  python3 - "$1" <<'PY'
import socket, sys, time

port = int(sys.argv[1])
for _ in range(200):
    s = socket.socket()
    s.settimeout(0.2)
    try:
        s.connect(("127.0.0.1", port))
        s.close()
        sys.exit(0)
    except OSError:
        s.close()
        time.sleep(0.05)
sys.exit(1)
PY
}

# Print the OpenCode manifest's IJ_MCP_SERVER_PROJECT_PATH header value.
_manifest_header() {
  python3 -c '
import json, sys
with open(sys.argv[1]) as fh:
    print(json.load(fh)["jetbrains"]["headers"]["IJ_MCP_SERVER_PROJECT_PATH"])
' "${PROJECT}/.opencode/jetbrains.mcp.json"
}

@test "jetbrains init: OpenCode header defaults to the portable {env:PWD} token" {
  run env PATH="${SHIM_DIR}:${PATH}" JETBRAINS_PORT="${FAKE_PORT}" \
    bash "${INIT_TOOL}" "${PROJECT}"
  assert_success

  run _manifest_header
  assert_success
  assert_output '{env:PWD}'
}

@test "jetbrains init: JETBRAINS_PROJECT_PATH override emits {env:JETBRAINS_PROJECT_PATH}" {
  run env PATH="${SHIM_DIR}:${PATH}" JETBRAINS_PORT="${FAKE_PORT}" \
    JETBRAINS_PROJECT_PATH="/host-side/project" bash "${INIT_TOOL}" "${PROJECT}"
  assert_success

  run _manifest_header
  assert_success
  assert_output '{env:JETBRAINS_PROJECT_PATH}'
}

@test "jetbrains init: manifest never bakes the resolved project path" {
  run env PATH="${SHIM_DIR}:${PATH}" JETBRAINS_PORT="${FAKE_PORT}" \
    bash "${INIT_TOOL}" "${PROJECT}"
  assert_success

  run grep -q "${PROJECT}" "${PROJECT}/.opencode/jetbrains.mcp.json"
  assert_failure
}
