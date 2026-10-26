#!/usr/bin/env bats
# =============================================================================
# src/harnesses/opencode/tests/reap_lsp_tests.bats
# Tests for lsp/reap.sh — the wrap-up reaper for LSP servers opencode left
# running. opencode spawns one server per directory it walks into and never
# tears a stale one down, so a long session accumulates idle intelephense /
# language-server processes that hold memory for the rest of the process's life.
#
# The reaper must be safe to run unattended at every wrap-up: it kills only
# servers that are provably not working (no CPU tick between two samples) or
# whose working directory has been removed (a deleted worktree), and it never
# touches a server that is actively indexing.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
  MODULE_DIR="$(cd "${TEST_DIR}/.." && pwd)"
  REAP="${MODULE_DIR}/lsp/reap.sh"

  SANDBOX="$(mktemp -d)"
  PIDS=()
}

teardown() {
  local pid
  for pid in "${PIDS[@]:-}"; do
    [[ -n "${pid}" ]] && kill "${pid}" 2>/dev/null || true
  done
  rm -r "${SANDBOX}" 2>/dev/null || true
}

# Spawn a stand-in for an opencode process tree: one parent owning
#   - IDLE: a language server that burns no CPU,
#   - BUSY: a language server that spins CPU (an active index),
#   - PLAIN: a non-LSP child that must never be touched,
#   - GONE: a busy server whose working directory the test will delete.
# The parent `wait`s, so the stubs keep it alive for the reaper to walk.
_start_fake_session() {
  local d="${SANDBOX}"
  mkdir -p "${d}/gone"

  bash -c '
    d="$1"
    bash -c "exec -a yaml-language-server sleep 60" &
    echo $! > "${d}/idle.pid"
    bash -c "exec -a gopls bash -c \"while :; do :; done\"" &
    echo $! > "${d}/busy.pid"
    bash -c "exec -a not-a-server sleep 60" &
    echo $! > "${d}/plain.pid"
    bash -c "cd \"${d}/gone\" && exec -a clangd bash -c \"while :; do :; done\"" &
    echo $! > "${d}/gone.pid"
    wait
  ' _ "${d}" &
  PARENT_PID=$!
  PIDS+=("${PARENT_PID}")

  local i
  for i in $(seq 1 50); do
    [[ -s "${d}/idle.pid" && -s "${d}/busy.pid" && -s "${d}/plain.pid" && -s "${d}/gone.pid" ]] && break
    sleep 0.1
  done

  IDLE_PID="$(cat "${d}/idle.pid")"
  BUSY_PID="$(cat "${d}/busy.pid")"
  PLAIN_PID="$(cat "${d}/plain.pid")"
  GONE_PID="$(cat "${d}/gone.pid")"
  PIDS+=("${IDLE_PID}" "${BUSY_PID}" "${PLAIN_PID}" "${GONE_PID}")
}

# Alive means "running", not merely "has a /proc entry" — a reaped child lingers
# as a zombie until its parent waits.
_stub_alive() {
  local state
  state="$(ps -o stat= -p "$1" 2>/dev/null || true)"
  [[ -n "${state}" && "${state}" != Z* ]]
}

@test "reap.sh: kills an idle LSP, spares a busy one" {
  _start_fake_session

  run bash "${REAP}" --parent "${PARENT_PID}" --log "${SANDBOX}/reap.log"

  assert_success
  sleep 0.3
  refute _stub_alive "${IDLE_PID}"
  assert _stub_alive "${BUSY_PID}"
}

@test "reap.sh: never touches a non-LSP child of the same process" {
  _start_fake_session

  run bash "${REAP}" --parent "${PARENT_PID}" --log "${SANDBOX}/reap.log"

  assert_success
  sleep 0.3
  assert _stub_alive "${PLAIN_PID}"
}

@test "reap.sh: kills a busy LSP whose working directory was removed" {
  _start_fake_session
  rm -r "${SANDBOX}/gone"

  run bash "${REAP}" --parent "${PARENT_PID}" --log "${SANDBOX}/reap.log"

  assert_success
  sleep 0.3
  refute _stub_alive "${GONE_PID}"
  run cat "${SANDBOX}/reap.log"
  assert_output --partial "deleted-cwd"
}

@test "reap.sh: --dry-run reports without killing" {
  _start_fake_session

  run bash "${REAP}" --parent "${PARENT_PID}" --log "${SANDBOX}/reap.log" --dry-run

  assert_success
  assert_output --partial "idle"
  sleep 0.3
  assert _stub_alive "${IDLE_PID}"
  [[ ! -s "${SANDBOX}/reap.log" ]]
}

@test "reap.sh: a tree with no LSP servers is a silent no-op" {
  bash -c 'sleep 60' &
  local plain_parent=$!
  PIDS+=("${plain_parent}")

  run bash "${REAP}" --parent "${plain_parent}" --log "${SANDBOX}/reap.log"

  assert_success
  assert_output ""
}
