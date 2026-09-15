#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/mcp_gateway_tests.bats
# Cross-cutting tests for the shared machine-wide MCP gateways.
#
# Review F5: the four module suites only asserted file SHAPE (manifest is http,
# compose contains the port, Dockerfile pins...). Nothing exercised the actual
# transport or the readiness wait, so the suite green-lit a gateway whose server
# never received its own environment. These tests cover:
#
#   1. The port is one fact, not five copies — compose mapping, canonical
#      manifest, module up.sh, Dockerfile EXPOSE and the docs registry must agree.
#   2. The readiness wait helper's three paths (ready / timeout / no curl).
#   3. A live gateway answers a real MCP handshake AND lists its tools
#      (docker required; skipped without a daemon or a running container).
#
# (1) and (2) need no docker and always run.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"
}

# module:host-port pairs — the single source of truth the tests enforce.
_gateways() {
  echo "mdctx:18501 signoz:18502 svelte:18503 codebase-memory:18504"
}

# ── 1. Port consistency ──────────────────────────────────────────────────────

@test "each gateway's port agrees across compose, manifest, up.sh, EXPOSE and docs" {
  local entry mod port fail=0
  for entry in $(_gateways); do
    mod="${entry%%:*}"
    port="${entry##*:}"
    local dir="${PROJECT_ROOT}/src/agentic/${mod}"

    # Canonical manifest URL.
    grep -q "127.0.0.1:${port}/mcp" "${dir}/mcp.json" 2>/dev/null \
      || { echo "manifest: ${mod} does not use 127.0.0.1:${port}/mcp"; fail=1; }

    # Compose host-side port mapping (the container-side port may differ).
    grep -q "127.0.0.1:${port}:" "${dir}/docker-compose.yml" 2>/dev/null \
      || { echo "compose: ${mod} does not map 127.0.0.1:${port}"; fail=1; }

    # Module up.sh probes the same URL.
    grep -q "127.0.0.1:${port}/mcp" "${dir}/up.sh" 2>/dev/null \
      || { echo "up.sh: ${mod} does not probe 127.0.0.1:${port}/mcp"; fail=1; }

    # Dockerfile, when the module builds its own image, must EXPOSE it.
    if [[ -f "${dir}/Dockerfile" ]]; then
      grep -q "EXPOSE ${port}" "${dir}/Dockerfile" \
        || { echo "Dockerfile: ${mod} does not EXPOSE ${port}"; fail=1; }
    fi

    # Documented in the port registry.
    grep -qE "\| *${port} *\| *${mod} *\|" "${PROJECT_ROOT}/docs/mcp-config.md" \
      || { echo "docs: port registry has no row for ${port} ${mod}"; fail=1; }
  done

  [ "${fail}" -eq 0 ]
}

@test "documented ports are unique and inside the 18500-18599 block" {
  local entry port seen="" fail=0
  for entry in $(_gateways); do
    port="${entry##*:}"
    if [[ "${port}" -lt 18500 || "${port}" -gt 18599 ]]; then
      echo "port ${port} is outside the reserved block"
      fail=1
    fi
    if [[ " ${seen} " == *" ${port} "* ]]; then
      echo "port ${port} is used by more than one gateway"
      fail=1
    fi
    seen="${seen} ${port}"
  done
  [ "${fail}" -eq 0 ]
}

@test "every gateway declares a healthcheck or says why it cannot" {
  # Review F14 / devbot:architecture-rules: a container must define its restart
  # policy and a health check. signoz's image is distroless — no shell, and none
  # of curl/wget/python3/node — so no probe can run inside it; that exception
  # must be stated in the file rather than left implicit.
  local entry mod compose fail=0
  for entry in $(_gateways); do
    mod="${entry%%:*}"
    compose="${PROJECT_ROOT}/src/agentic/${mod}/docker-compose.yml"

    if grep -qE '^    healthcheck:' "${compose}"; then
      # The probe must hit this gateway's own port.
      grep -q "127.0.0.1:${entry##*:}/mcp" "${compose}" \
        || { echo "${mod}: healthcheck does not probe its own port"; fail=1; }
    else
      grep -qi 'NO healthcheck' "${compose}" \
        || { echo "${mod}: no healthcheck and no explanation why"; fail=1; }
    fi

    # Restart policy must be deliberate and documented, not incidental.
    grep -qE '^    restart: "no"' "${compose}" \
      || { echo "${mod}: unexpected restart policy"; fail=1; }
    grep -q 'Deliberately NOT' "${compose}" \
      || { echo "${mod}: restart policy is not documented"; fail=1; }
  done
  [ "${fail}" -eq 0 ]
}

# ── 2. Readiness wait helper ─────────────────────────────────────────────────

# Build a PATH whose only tool is a `curl` stub with the given exit code.
_curl_stub_path() {
  local exit_code="$1"
  local dir
  dir="$(mktemp -d)"
  cat > "${dir}/curl" <<MOCK
#!/usr/bin/env bash
exit ${exit_code}
MOCK
  chmod +x "${dir}/curl"
  echo "${dir}"
}

@test "wait helper returns 0 when the gateway answers" {
  local stub
  stub="$(_curl_stub_path 0)"

  run bash -c "
    source '${PROJECT_ROOT}/src/_shared/functions.sh'
    PATH='${stub}:'\$PATH
    _devbot_wait_for_mcp_gateway testgw http://127.0.0.1:1/mcp 2
    echo \"rc=\$?\"
  "

  assert_success
  assert_output --partial 'rc=0'
  rm -rf "${stub}"
}

@test "wait helper reports a skip and returns 1 on timeout" {
  local stub
  stub="$(_curl_stub_path 1)"

  run bash -c "
    source '${PROJECT_ROOT}/src/_shared/functions.sh'
    PATH='${stub}:'\$PATH
    DEV_BOT_MCP_WAIT_TRIES=1 _devbot_wait_for_mcp_gateway testgw http://127.0.0.1:1/mcp
    echo \"rc=\$?\"
  "

  assert_output --partial 'rc=1'
  assert_output --partial 'not reachable'
  rm -rf "${stub}"
}

@test "wait helper skips when curl is unavailable" {
  run bash -c "
    source '${PROJECT_ROOT}/src/_shared/functions.sh'
    PATH=/nonexistent
    _devbot_wait_for_mcp_gateway testgw http://127.0.0.1:1/mcp 1
    echo \"rc=\$?\"
  "

  assert_output --partial 'rc=1'
  assert_output --partial 'curl not available'
}

@test "every gateway module up.sh delegates to the shared wait helper" {
  # Guards against a module re-inlining its own wait loop (four copies is what
  # made the behaviour untestable in the first place).
  local entry mod fail=0
  for entry in $(_gateways); do
    mod="${entry%%:*}"
    grep -q '_devbot_wait_for_mcp_gateway' "${PROJECT_ROOT}/src/agentic/${mod}/up.sh" \
      || { echo "${mod}/up.sh does not call _devbot_wait_for_mcp_gateway"; fail=1; }
  done
  [ "${fail}" -eq 0 ]
}

# ── 3. Script hygiene for the gateway modules ────────────────────────────────

@test "gateway module scripts end with a newline" {
  # Review F11: rewritten signoz scripts lost their trailing newline.
  #
  # NOT asserted here: ${BASH_SOURCE[0]} vs $0. The documented convention
  # (docs/create-a-module.md) is BASH_SOURCE, but $0 persists in ~37 pre-existing
  # short scripts across the tree — an unrelated pre-existing drift, not part of
  # this changeset. Tracked as a follow-up rather than enforced for four modules
  # while the rest of the tree disagrees.
  local entry mod f fail=0
  for entry in $(_gateways); do
    mod="${entry%%:*}"
    for f in "${PROJECT_ROOT}/src/agentic/${mod}"/*.sh; do
      [[ -f "${f}" ]] || continue
      if [[ -n "$(tail -c 1 "${f}")" ]]; then
        echo "${f#${PROJECT_ROOT}/} does not end with a newline"
        fail=1
      fi
    done
  done
  [ "${fail}" -eq 0 ]
}

# ── 4. Live gateway (docker required) ────────────────────────────────────────
# POST an MCP initialize, capturing both the response body and the session id
# the streamable-http transport requires on subsequent requests. A stateless
# server (signoz speaks native HTTP) issues no session id at all.
_mcp_initialize() {
  local url="$1"
  local headers
  headers="$(mktemp)"

  MCP_INIT_BODY="$(curl -s -D "${headers}" --max-time 15 -X POST "${url}" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"dev-bot-test","version":"1"}}}' 2>/dev/null \
    | sed 's/^data: //' | grep '^{' | tail -1)"
  MCP_INIT_SESSION="$(tr -d '\r' < "${headers}" | awk -F': ' 'tolower($1)=="mcp-session-id"{print $2}' | head -1)"

  rm -f "${headers}"
}

# POST a JSON-RPC request (carrying the session id when there is one) and print
# the SSE data payload.
_mcp_call() {
  local url="$1" sid="$2" body="$3"
  local hdr=()
  [[ -n "${sid}" ]] && hdr=(-H "mcp-session-id: ${sid}")
  curl -s --max-time 15 -X POST "${url}" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' \
    ${hdr[@]+"${hdr[@]}"} \
    -d "${body}" 2>/dev/null | sed 's/^data: //' | grep '^{' | tail -1
}

@test "running gateways answer a real initialize and list their tools" {
  command -v docker >/dev/null 2>&1 || skip "docker not installed"
  docker info >/dev/null 2>&1 || skip "no docker daemon available"

  local entry mod port checked=0 fail=0
  for entry in $(_gateways); do
    mod="${entry%%:*}"
    port="${entry##*:}"

    # Only test gateways whose container is actually running.
    docker ps --filter "name=dev-bot-${mod}-mcp" --format '{{.Names}}' 2>/dev/null \
      | grep -q . || continue
    checked=$((checked + 1))

    local url="http://127.0.0.1:${port}/mcp"

    # A real MCP handshake.
    MCP_INIT_BODY=""
    MCP_INIT_SESSION=""
    _mcp_initialize "${url}"
    if ! grep -q '"serverInfo"' <<< "${MCP_INIT_BODY}"; then
      echo "${mod}: no serverInfo in the initialize response: ${MCP_INIT_BODY:0:160}"
      fail=1
      continue
    fi

    # The server must actually be usable — tools/list is served by the spawned
    # stdio process, so a server whose environment never arrived (the
    # --pass-environment incident) is caught here rather than passing on the
    # handshake alone.
    local tools
    tools="$(_mcp_call "${url}" "${MCP_INIT_SESSION}" '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}')"
    if ! grep -q '"tools"' <<< "${tools}"; then
      echo "${mod}: tools/list returned no tools: ${tools:0:160}"
      fail=1
    fi
  done

  [[ "${checked}" -gt 0 ]] || skip "no gateway containers running — start them with 'devbot up'"
  [ "${fail}" -eq 0 ]
}
