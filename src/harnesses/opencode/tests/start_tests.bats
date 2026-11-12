#!/usr/bin/env bats
# =============================================================================
# src/harnesses/opencode/tests/start_tests.bats
# Tests for opencode/start.sh — the launcher used by `devbot` to start
# OpenCode. The session agent is not forced at launch; it comes from the
# project's opencode.jsonc `default_agent` (set during init).
#
# Validates that:
#   - start.sh launches opencode without forcing an agent
#   - extra CLI args are forwarded unchanged
#   - a missing opencode binary fails loudly with a FATAL message
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # Non-GUI tests must not inherit a --gui switch from the environment the
  # suite runs in (a Claude/OpenCode app opened by `devbot --gui` carries it).
  unset DEV_BOT_GUI

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"

  # The script resolves the binary at ${HOME}/.opencode/bin/opencode, so
  # point HOME at a sandbox holding a fake binary that records its args. It
  # answers --version like a real opencode (the launch runs the 1.x guard,
  # which probes the version first).
  FAKE_HOME="$(mktemp -d)"
  FAKE_PROJECT="$(mktemp -d)"
  FAKE_ROOT="$(mktemp -d)"
  mkdir -p "${FAKE_HOME}/.opencode/bin"

  cat > "${FAKE_HOME}/.opencode/bin/opencode" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  printf '1.18.35\n'
  exit 0
fi
printf '%s\n' "$*"
EOF
  chmod +x "${FAKE_HOME}/.opencode/bin/opencode"
}

# ── Env-var gate fixture ─────────────────────────────────────────────────────
# A fake dev-bot root whose single enabled module references an env var, so
# _devbot_check_mcp_env_vars (gate) has something to check. memory is disabled
# so start.sh's detached prune preamble no-ops fast.
_make_env_gate_root() {
  mkdir -p "${FAKE_ROOT}/src/tools" "${FAKE_ROOT}/src/agentic/envmod" "${FAKE_ROOT}/src/harnesses"
  echo '{ "modules": { "memory": false } }' > "${FAKE_ROOT}/.devbot.global.jsonc"
  cat > "${FAKE_ROOT}/src/agentic/envmod/mcp.json" <<'JSON_EOF'
{
  "mcp": {
    "envmod-server": {
      "type": "stdio",
      "command": ["envmod-mcp"],
      "env": { "ENVMOD_TOKEN": "{env:DEV_TEST_MCP_TOKEN}" }
    }
  }
}
JSON_EOF
}

# ── Hermetic root fixture ────────────────────────────────────────────────────
# A module-free dev-bot root, so start.sh's MCP env-var gate finds nothing to
# check. A test that omits DEV_BOT_ROOT scans the REAL module inventory instead,
# and breaks the moment any enabled module references an unset env var — the
# assertions below are exact-match on the forwarded args.
_make_minimal_root() {
  mkdir -p "${FAKE_ROOT}/src/tools" "${FAKE_ROOT}/src/agentic" "${FAKE_ROOT}/src/harnesses"
  echo '{ "modules": { "memory": false } }' > "${FAKE_ROOT}/.devbot.global.jsonc"
}

@test "start.sh warns about unset MCP env vars and still launches (non-interactive)" {
  _make_env_gate_root
  unset DEV_TEST_MCP_TOKEN
  DEV_BOT_ROOT="${FAKE_ROOT}" HOME="${FAKE_HOME}" \
    run "${BASH}" "${MODULE_DIR}/start.sh" "${FAKE_PROJECT}"
  assert_success
  assert_output --partial "DEV_TEST_MCP_TOKEN"
  assert_output --partial "envmod"
  assert_output --partial ".bashrc"
}

@test "start.sh launches cleanly when MCP env vars are set" {
  _make_env_gate_root
  export DEV_TEST_MCP_TOKEN="present"
  DEV_BOT_ROOT="${FAKE_ROOT}" HOME="${FAKE_HOME}" \
    run "${BASH}" "${MODULE_DIR}/start.sh" "${FAKE_PROJECT}"
  assert_success
  refute_output --partial "DEV_TEST_MCP_TOKEN"
  refute_output --partial "envmod"
  unset DEV_TEST_MCP_TOKEN
}

teardown() {
  rm -rf "${FAKE_HOME}" "${FAKE_PROJECT}" "${FAKE_ROOT}"
}

@test "start.sh launches opencode without forcing an agent" {
  HOME="${FAKE_HOME}" run "${BASH}" "${MODULE_DIR}/start.sh" "${FAKE_PROJECT}"
  assert_success
  refute_output --partial "--agent"
}

@test "start.sh forwards extra args to opencode" {
  _make_minimal_root
  DEV_BOT_ROOT="${FAKE_ROOT}" HOME="${FAKE_HOME}" \
    run "${BASH}" "${MODULE_DIR}/start.sh" "${FAKE_PROJECT}" --continue
  assert_success
  assert_output "--continue"
}

@test "start.sh fails loudly when opencode binary is missing" {
  EMPTY_HOME="$(mktemp -d)"
  HOME="${EMPTY_HOME}" run "${BASH}" "${MODULE_DIR}/start.sh" "${FAKE_PROJECT}"
  rm -rf "${EMPTY_HOME}"
  assert_failure
  local combined="${output}${stderr:-}"
  [[ "${combined}" == *"opencode binary not found"* ]]
}

@test "start.sh propagates the harness exit code" {
  cat > "${FAKE_HOME}/.opencode/bin/opencode" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*"
exit 42
STUB
  chmod +x "${FAKE_HOME}/.opencode/bin/opencode"

  HOME="${FAKE_HOME}" run "${BASH}" "${MODULE_DIR}/start.sh" "${FAKE_PROJECT}"
  assert_failure
  [ "$status" -eq 42 ]
}

@test "start.sh alerts when the session wrote error logs" {
  cat > "${FAKE_HOME}/.opencode/bin/opencode" <<'STUB'
#!/usr/bin/env bash
mkdir -p .agents/logs
printf 'ERROR: boom\n' >> .agents/logs/hooks.log
printf '%s\n' "$*"
STUB
  chmod +x "${FAKE_HOME}/.opencode/bin/opencode"

  HOME="${FAKE_HOME}" run "${BASH}" "${MODULE_DIR}/start.sh" "${FAKE_PROJECT}"
  assert_success
  assert_output --partial "ERROR: boom"
  assert_output --partial "hooks.log"
}

@test "start.sh does not alert on qmd graceful-degradation lines (audit-45 §4)" {
  # qmd's query-time reranker/query-expansion skip with an InsufficientMemoryError
  # when the shared GPU lacks VRAM; search still works (degraded). Those lines
  # contain 'failed' but must NOT trip the session-end alert.
  cat > "${FAKE_HOME}/.opencode/bin/opencode" <<'STUB'
#!/usr/bin/env bash
mkdir -p .agents/logs
printf 'Structured query expansion failed: InsufficientMemoryError: A context size of 512 is too large for the available VRAM\n' >> .agents/logs/qmd-mcp.log
printf 'Reranker unavailable — skipping reranking (A context size of 4096 is too large for the available VRAM)\n' >> .agents/logs/qmd-mcp.log
printf 'QMD Warning: no GPU acceleration, running on CPU (slow)\n' >> .agents/logs/qmd-mcp.log
printf '%s\n' "$*"
STUB
  chmod +x "${FAKE_HOME}/.opencode/bin/opencode"

  HOME="${FAKE_HOME}" run "${BASH}" "${MODULE_DIR}/start.sh" "${FAKE_PROJECT}"
  assert_success
  refute_output --partial "Session finished with error log entries"
}

@test "start.sh still alerts on a genuine error beside qmd degradation lines" {
  cat > "${FAKE_HOME}/.opencode/bin/opencode" <<'STUB'
#!/usr/bin/env bash
mkdir -p .agents/logs
printf 'Structured query expansion failed: InsufficientMemoryError: x\n' >> .agents/logs/qmd-mcp.log
printf 'ERROR: real crash\n' >> .agents/logs/qmd-mcp.log
printf '%s\n' "$*"
STUB
  chmod +x "${FAKE_HOME}/.opencode/bin/opencode"

  HOME="${FAKE_HOME}" run "${BASH}" "${MODULE_DIR}/start.sh" "${FAKE_PROJECT}"
  assert_success
  assert_output --partial "Session finished with error log entries"
  assert_output --partial "qmd-mcp.log"
}

@test "start.sh fires the detached memory prune before launching (memory vault + qmd)" {
  # audit-36: the delete→prune self-heal (qmd cleanup && qmd update, no embed)
  # moved from the session.created hook to start.sh, fired detached before the
  # harness so it runs per launch and qmd gets a head start ahead of the MCP
  # fleet boot at session start (audit-34 NOTE-8 / audit-35 FAIL).
  mkdir -p "${FAKE_PROJECT}/.agents/memory/latent/learnings"

  local fake_qmd call_log
  fake_qmd="$(mktemp -d)"
  cat > "${fake_qmd}/qmd" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "${QMD_CALL_LOG:?}"
  state="${QMD_CALL_LOG}.collection"
  case "${1:-} ${2:-}" in
    "collection show")
      path="$(cat "$state" 2>/dev/null || true)"
      [[ -n "$path" ]] || exit 1
      printf 'Path: %s\n' "$path"
      ;;
    "collection add") printf '%s\n' "${3:-}" > "$state" ;;
    "collection remove") : > "$state" ;;
  esac
EOF
  chmod +x "${fake_qmd}/qmd"
  call_log="$(mktemp)"

  HOME="${FAKE_HOME}" PATH="${fake_qmd}:${PATH}" QMD_CALL_LOG="${call_log}" \
    DEVBOT_MEMORY_SEARCH_PROVIDER=qmd run "${BASH}" "${MODULE_DIR}/start.sh" "${FAKE_PROJECT}"

  assert_success
  # The helper writes its marker synchronously; the engine work runs detached.
  # Log target is memory-index.log (engine-agnostic name for qmd and mdctx).
  run cat "${FAKE_PROJECT}/.agents/logs/memory-index.log"
  assert_output --partial "reindex-memories-prune-start"

  local i
  for i in $(seq 1 50); do
    grep -qx "update" "${call_log}" 2>/dev/null && break
    sleep 0.1
  done
  run cat "${call_log}"
  # A migration probe (collection show) may precede the rebuild; the rebuild
  # itself must still run cleanup before update.
  assert_output --partial "cleanup"
  assert_output --partial "update"
  local cleanup_line update_line
  cleanup_line="$(grep -n "cleanup" "${call_log}" | head -1 | cut -d: -f1 || echo 0)"
  update_line="$(grep -n "update" "${call_log}" | head -1 | cut -d: -f1 || echo 0)"
  [[ "$cleanup_line" -gt 0 && "$update_line" -gt 0 && "$cleanup_line" -lt "$update_line" ]]

  rm -rf "${fake_qmd}" "${call_log}"
}

# ── external_directory reconciliation (init.sh) ──────────────────────────────
# audit-22 FAIL: a /tmp/** allow placed before the catch-all "*" deny is
# shadowed (last-match-wins), leaving the pre-approved scratch dir
# unreachable. init.sh must reconcile existing configs to deny-first order on
# every reinit, not just new ones.

assert_external_directory_deny_first() {
  run python3 -c "
import json, re, sys
text = open('${FAKE_PROJECT}/opencode.jsonc').read()
m = re.search(r'\"external_directory\"\s*:\s*\{([^}]*)\}', text, re.S)
entries = json.loads('{' + m.group(1) + '}')
sys.exit(0 if list(entries.keys())[0] == '*' else 1)
"
  assert_success
}

@test "reconcile: moves /tmp/** allow after the catch-all deny (stale order)" {
  printf '{\n  "permission": {\n    "external_directory": {\n      "/tmp/**": "allow",\n      "*": "deny"\n    }\n  }\n}\n' > "${FAKE_PROJECT}/opencode.jsonc"

  run bash "${MODULE_DIR}/init.sh" "${FAKE_PROJECT}"
  assert_success

  assert_external_directory_deny_first
}

@test "reconcile: inserts /tmp/** after the deny when absent" {
  printf '{\n  "permission": {\n    "external_directory": {\n      "*": "deny"\n    }\n  }\n}\n' > "${FAKE_PROJECT}/opencode.jsonc"

  run bash "${MODULE_DIR}/init.sh" "${FAKE_PROJECT}"
  assert_success

  assert_external_directory_deny_first
  run grep -q '"/tmp/\*\*": "allow"' "${FAKE_PROJECT}/opencode.jsonc"
  assert_success
}

@test "reconcile: allows the opencode harness log dir (audit-51 §8b)" {
  # A deny-first block with /tmp/** but no opencode-log allow is still
  # reconciled so the agent can read the harness log in-band.
  printf '{\n  "permission": {\n    "external_directory": {\n      "*": "deny",\n      "/tmp/**": "allow"\n    }\n  }\n}\n' > "${FAKE_PROJECT}/opencode.jsonc"

  run bash "${MODULE_DIR}/init.sh" "${FAKE_PROJECT}"
  assert_success

  run grep -q '"'"${HOME}/.local/share/opencode/log/\*\*"'": "allow"' "${FAKE_PROJECT}/opencode.jsonc"
  assert_success
  run grep -q '"'"${HOME}/.config/opencode/\*\*"'": "allow"' "${FAKE_PROJECT}/opencode.jsonc"
  assert_success
}

@test "reconcile: log allow survives a second init run (no duplicate)" {
  printf '{\n  "permission": {\n    "external_directory": {\n      "*": "deny",\n      "/tmp/**": "allow"\n    }\n  }\n}\n' > "${FAKE_PROJECT}/opencode.jsonc"

  run bash "${MODULE_DIR}/init.sh" "${FAKE_PROJECT}"
  assert_success
  run bash "${MODULE_DIR}/init.sh" "${FAKE_PROJECT}"
  assert_success

  run grep -c '"'"${HOME}/.local/share/opencode/log/\*\*"'": "allow"' "${FAKE_PROJECT}/opencode.jsonc"
  assert_equal "$output" "1"
}

# ── Harness-log cap ───────────────────────────────────────────────────────────
# The opencode log grows without bound (100 MB on a dev machine, never rotated);
# start.sh rotates it past the cap before launching (audit-69 NOTE-2).

@test "start.sh caps an oversized opencode log" {
  _make_minimal_root
  local logdir="${FAKE_HOME}/.local/share/opencode/log"
  mkdir -p "${logdir}"
  head -c 200 /dev/zero > "${logdir}/opencode.log"

  DEV_BOT_ROOT="${FAKE_ROOT}" HOME="${FAKE_HOME}" DEV_BOT_OPENCODE_LOG_MAX_BYTES=100 \
    run "${BASH}" "${MODULE_DIR}/start.sh" "${FAKE_PROJECT}"

  assert_success
  [[ -e "${logdir}/opencode.log.1" ]]
  [[ ! -e "${logdir}/opencode.log" ]]
}

@test "start.sh leaves a small opencode log alone" {
  _make_minimal_root
  local logdir="${FAKE_HOME}/.local/share/opencode/log"
  mkdir -p "${logdir}"
  printf 'small\n' > "${logdir}/opencode.log"

  DEV_BOT_ROOT="${FAKE_ROOT}" HOME="${FAKE_HOME}" \
    run "${BASH}" "${MODULE_DIR}/start.sh" "${FAKE_PROJECT}"

  assert_success
  [[ -e "${logdir}/opencode.log" ]]
  [[ ! -e "${logdir}/opencode.log.1" ]]
}

# ── GUI mode (devbot --gui → DEV_BOT_GUI=1) ───────────────────────────────────
# The desktop app replaces the CLI: no CLI binary is needed, `open` is called
# with the app's bundle id and the project's deep link, and the launcher then
# HOLDS (the devbot session and its docker services must outlive `open`).

# Put a stub `open` first on PATH; it records its argv and exits OPEN_RC.
_make_open_stub() {
  # This file's setup has no FAKE_BIN; keep the stub inside FAKE_HOME so the
  # existing teardown removes it.
  FAKE_BIN="${FAKE_HOME}/bin"
  mkdir -p "${FAKE_BIN}"
  OPEN_LOG="${FAKE_BIN}/open.log"
  cat > "${FAKE_BIN}/open" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$@" > "${OPEN_LOG}"
exit "\${OPEN_RC:-0}"
STUB
  chmod +x "${FAKE_BIN}/open"
}

# Start start.sh in GUI mode in the background; LAUNCHER_PID is the shell's own
# pid (exec), so a signal reaches the launcher and not a wrapper subshell.
_start_gui() {
  ( exec env HOME="${FAKE_HOME}" DEV_BOT_GUI=1 DEV_BOT_ROOT="${FAKE_ROOT}" PATH="${FAKE_BIN}:/usr/bin:/bin" \
      "${BASH}" "${MODULE_DIR}/start.sh" "${FAKE_PROJECT}" ) >"${FAKE_BIN}/out.log" 2>&1 &
  LAUNCHER_PID=$!
}

_wait_for_file() {
  local i
  for i in $(seq 1 100); do
    [[ -s "$1" ]] && return 0
    sleep 0.1
  done
  return 1
}

@test "start.sh --gui opens the OpenCode desktop app on the project and holds until TERM" {
  _make_minimal_root
  _make_open_stub
  rm -f "${FAKE_HOME}/.opencode/bin/opencode"
  local encoded
  encoded="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "${FAKE_PROJECT}")"

  _start_gui
  _wait_for_file "${OPEN_LOG}"
  # Still alive after `open` returned: the session must not be released yet.
  sleep 3
  kill -0 "${LAUNCHER_PID}"

  run cat "${OPEN_LOG}"
  assert_line --index 0 "-b"
  assert_line --index 1 "ai.opencode.desktop"
  assert_line --index 2 "opencode://open-project?directory=${encoded}"

  kill -TERM "${LAUNCHER_PID}"
  local status=0
  wait "${LAUNCHER_PID}" || status=$?
  [ "${status}" -eq 0 ]
}

@test "start.sh --gui does not need the CLI binary" {
  _make_minimal_root
  _make_open_stub
  rm -f "${FAKE_HOME}/.opencode/bin/opencode"
  _start_gui
  _wait_for_file "${OPEN_LOG}"
  kill -TERM "${LAUNCHER_PID}"
  wait "${LAUNCHER_PID}" || true
  run cat "${FAKE_BIN}/out.log"
  refute_output --partial "binary not found"
}

@test "start.sh --gui fails loudly when the desktop app is not installed" {
  _make_minimal_root
  _make_open_stub
  rm -f "${FAKE_HOME}/.opencode/bin/opencode"
  DEV_BOT_GUI=1 OPEN_RC=1 DEV_BOT_ROOT="${FAKE_ROOT}" HOME="${FAKE_HOME}" PATH="${FAKE_BIN}:/usr/bin:/bin" \
    run "${BASH}" "${MODULE_DIR}/start.sh" "${FAKE_PROJECT}"
  assert_failure
  assert_output --partial "OpenCode desktop app not found"
}
