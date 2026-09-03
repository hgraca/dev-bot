#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/mcp-stdio-wrapper_tests.bats
# Tests for mcp-stdio-wrapper.js (the MCP stdio EPIPE swallow).
#
# npx-launched stdio MCP servers (playwright, chrome-devtools, codebase-index)
# crash with an unhandled EPIPE when the MCP client closes the stdio pipe at
# session teardown (audit-18/19 NOTEs). The wrapper bridges stdio and swallows
# that teardown EPIPE. Tests use fake child commands — no playwright, no
# docker, no network.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  WRAPPER="$TEST_DIR/../mcp-stdio-wrapper.js"

  FAKE_BIN="$(mktemp -d)"
}

teardown() {
  rm -rf "${FAKE_BIN}"
}

# ── Wrapper behaviour ─────────────────────────────────────────────────────────

@test "wrapper: forwards child stdout and exits 0" {
  local child="${FAKE_BIN}/echo.sh"
  cat > "${child}" <<'EOF'
#!/usr/bin/env bash
printf 'hello from mcp server\n'
exit 0
EOF
  chmod +x "${child}"

  run node "${WRAPPER}" bash "${child}"

  assert_success
  assert_output "hello from mcp server"
}

@test "wrapper: propagates the child's non-zero exit code" {
  local child="${FAKE_BIN}/fail.sh"
  cat > "${child}" <<'EOF'
#!/usr/bin/env bash
echo "boom" >&2
exit 3
EOF
  chmod +x "${child}"

  run node "${WRAPPER}" bash "${child}"

  assert_failure 3
}

@test "wrapper: usage error without a command (exit 2)" {
  run node "${WRAPPER}"

  assert_failure 2
  assert_output --partial "Usage:"
}

@test "wrapper: reports a spawn failure (missing command) with exit 1" {
  run node "${WRAPPER}" /nonexistent-command-xyz

  assert_failure 1
  assert_output --partial "failed to spawn"
}

@test "wrapper: survives the client closing stdout early (EPIPE swallow)" {
  # The child emits ~1MB — far more than the 64KB kernel pipe buffer — so the
  # wrapper is still writing when the reader (head) closes the pipe after the
  # first line. Without the stdout 'error' listener, node dies on the first
  # EPIPE with exit 1; with it, the wrapper drains and exits 0.
  local child="${FAKE_BIN}/spew.sh"
  cat > "${child}" <<'EOF'
#!/usr/bin/env bash
for i in $(seq 1 20000); do
  printf 'line-%05d-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\n' "$i"
done
exit 0
EOF
  chmod +x "${child}"

  run bash -c 'set -o pipefail
node "$1" bash "$2" 2>/dev/null | head -n 1 >/dev/null
printf "node=%s\n" "${PIPESTATUS[0]}"
' _ "${WRAPPER}" "${child}"

  assert_success
  assert_output --partial "node=0"
}

# ── Child-process EPIPE guard (audit-35 FAIL) ─────────────────────────────────
# npx/node-launched MCP servers (chrome-devtools-mcp, @playwright/mcp,
# codebase-index-mcp) crash with an unhandled EPIPE when the client tears the
# wrapper down mid-handshake (e.g. a 30s CONNECT_TIMEOUT at session start): the
# wrapper's own stdout 'error' listener cannot cover the child, which lives in
# a separate process. The wrapper preloads a guard (NODE_OPTIONS=--require=<
# mcp-epipe-guard.js>) into node/npx children so the child's own stdout EPIPE
# exits cleanly (code 0) instead of crash-logging a raw stack trace.

write_node_spew_child() {
  cat > "${1}" <<'EOF'
#!/usr/bin/env node
// Writes far more than the 64KB pipe buffer, so a reader (head -n 1) that
// closes after the first line forces an EPIPE on a later write.
const chunk = "x".repeat(1024)
for (let i = 0; i < 20000; i++) {
  process.stdout.write(chunk + "\n")
}
EOF
  chmod +x "${1}"
}

@test "wrapper: injects the EPIPE guard via NODE_OPTIONS into node/npx children" {
  run env -u NODE_OPTIONS node "${WRAPPER}" node -e \
    'console.log(process.env.NODE_OPTIONS || "none")'

  assert_success
  assert_output --regexp '--require=.*mcp-epipe-guard\.js'
}

@test "wrapper: does not inject NODE_OPTIONS for non-node commands (docker/bash)" {
  run env -u NODE_OPTIONS node "${WRAPPER}" bash -c 'echo "${NODE_OPTIONS:-none}"'

  assert_success
  assert_output "none"
}

@test "guard: node child EPIPE exits 0 with the guard preloaded" {
  local child="${FAKE_BIN}/spew.js"
  write_node_spew_child "${child}"
  local guard
  guard="$(dirname "${WRAPPER}")/mcp-epipe-guard.js"

  run bash -c 'set -o pipefail
node --require="$1" "$2" 2>"$3" | head -n 1 >/dev/null
printf "node=%s\n" "${PIPESTATUS[0]}"
printf "unhandled=%s\n" "$(grep -c "Unhandled" "$3" || true)"
' _ "${guard}" "${child}" "${FAKE_BIN}/guard-err.log"

  assert_success
  assert_output --partial "node=0"
  assert_output --partial "unhandled=0"
}

@test "guard: same child crashes without the guard (control)" {
  local child="${FAKE_BIN}/spew.js"
  write_node_spew_child "${child}"

  run bash -c 'set -o pipefail
node "$2" 2>"$3" | head -n 1 >/dev/null
printf "node=%s\n" "${PIPESTATUS[0]}"
printf "unhandled=%s\n" "$(grep -c "Unhandled" "$3" || true)"
' _ _ "${child}" "${FAKE_BIN}/no-guard-err.log"

  assert_success
  assert_output --partial "node=1"
  assert_output --partial "unhandled=1"
}

@test "guard: NODE_OPTIONS propagates through npx to the spawned server" {
  command -v npx >/dev/null 2>&1 || skip "npx not installed"
  # audit-40-style crash chain: the wrapper spawns `npx -y <mcp-server>` and the
  # server's OWN stdout is what EPIPEs at teardown — so the guard must survive
  # the npx hop and load inside the actual server process. Hermetic: a local
  # fake-server package resolved with `npx --no-install` — no network.
  local proj
  proj="$(mktemp -d)"
  mkdir -p "${proj}/node_modules/fake-server" "${proj}/node_modules/.bin"
  printf '{"name":"fake-server","version":"1.0.0","bin":{"fake-server":"./server.js"}}\n' \
    > "${proj}/node_modules/fake-server/package.json"
  cat > "${proj}/node_modules/fake-server/server.js" <<'EOF'
#!/usr/bin/env node
console.log("server NODE_OPTIONS=" + (process.env.NODE_OPTIONS || "unset"))
EOF
  chmod +x "${proj}/node_modules/fake-server/server.js"
  ln -s ../fake-server/server.js "${proj}/node_modules/.bin/fake-server"

  run bash -c 'cd "$1" && node "$2" npx --no-install fake-server' \
    _ "${proj}" "${WRAPPER}"

  assert_success
  assert_output --partial "server NODE_OPTIONS=--require="
  assert_output --partial "mcp-epipe-guard.js"

  rm -rf "${proj}"
}
