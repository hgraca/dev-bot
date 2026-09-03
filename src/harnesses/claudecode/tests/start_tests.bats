#!/usr/bin/env bats
# =============================================================================
# src/harnesses/claudecode/tests/start_tests.bats
# Tests for claudecode/start.sh — the launcher used by `devbot` to start
# Claude Code. The session agent is not forced at launch; it comes from
# .claude/settings.json `agent` (set during init).
#
# Validates that:
#   - start.sh launches claude without forcing an agent
#   - extra CLI args are forwarded unchanged
#   - a missing claude binary fails loudly with a FATAL message
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"

  FAKE_BIN="$(mktemp -d)"
  FAKE_PROJECT="$(mktemp -d)"

  # Fake claude records its CLI args — start.sh must `exec` it, so the
  # recorded output is exactly what the real claude would receive.
  cat > "${FAKE_BIN}/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*"
EOF
  chmod +x "${FAKE_BIN}/claude"
}

teardown() {
  rm -rf "${FAKE_BIN}" "${FAKE_PROJECT}"
}

@test "start.sh launches claude without forcing an agent" {
  PATH="${FAKE_BIN}:${PATH}" run "${BASH}" "${MODULE_DIR}/start.sh" "${FAKE_PROJECT}"
  assert_success
  refute_output --partial "--agent"
}

@test "start.sh forwards extra args to claude" {
  PATH="${FAKE_BIN}:${PATH}" run "${BASH}" "${MODULE_DIR}/start.sh" "${FAKE_PROJECT}" --continue
  assert_success
  assert_output "--continue"
}

@test "start.sh fails loudly when claude is missing" {
  # No fake claude, and no ~/.local/bin (where the real claude lives):
  # only /usr/bin + /bin so the script itself can still run.
  PATH="/usr/bin:/bin" run "${BASH}" "${MODULE_DIR}/start.sh" "${FAKE_PROJECT}"
  assert_failure
  local combined="${output}${stderr:-}"
  [[ "${combined}" == *"claude binary not found"* ]]
}

@test "start.sh propagates the harness exit code" {
  cat > "${FAKE_BIN}/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*"
exit 42
STUB
  chmod +x "${FAKE_BIN}/claude"

  PATH="${FAKE_BIN}:${PATH}" run "${BASH}" "${MODULE_DIR}/start.sh" "${FAKE_PROJECT}"
  assert_failure
  [ "$status" -eq 42 ]
}

@test "start.sh alerts when the session wrote error logs" {
  cat > "${FAKE_BIN}/claude" <<'STUB'
#!/usr/bin/env bash
mkdir -p .agents/logs
printf 'ERROR: boom\n' >> .agents/logs/hooks.log
printf '%s\n' "$*"
STUB
  chmod +x "${FAKE_BIN}/claude"

  PATH="${FAKE_BIN}:${PATH}" run "${BASH}" "${MODULE_DIR}/start.sh" "${FAKE_PROJECT}"
  assert_success
  assert_output --partial "ERROR: boom"
  assert_output --partial "hooks.log"
}

@test "start.sh rotates pre-session logs and alerts only on new errors" {
  mkdir -p "${FAKE_PROJECT}/.agents/logs"
  printf 'ERROR: old boom\n' > "${FAKE_PROJECT}/.agents/logs/hooks.log"

  cat > "${FAKE_BIN}/claude" <<'STUB'
#!/usr/bin/env bash
mkdir -p .agents/logs
printf 'ERROR: new boom\n' >> .agents/logs/hooks.log
printf '%s\n' "$*"
STUB
  chmod +x "${FAKE_BIN}/claude"

  PATH="${FAKE_BIN}:${PATH}" run "${BASH}" "${MODULE_DIR}/start.sh" "${FAKE_PROJECT}"
  assert_success
  assert_output --partial "ERROR: new boom"
  refute_output --partial "ERROR: old boom"

  # The previous session's log is preserved under rotated/.
  run find "${FAKE_PROJECT}/.agents/logs/rotated" -name "*-hooks-*.log" -print
  assert_output --partial "hooks"
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
exit 0
EOF
  chmod +x "${fake_qmd}/qmd"
  call_log="$(mktemp)"

  PATH="${fake_qmd}:${FAKE_BIN}:${PATH}" QMD_CALL_LOG="${call_log}" \
    run "${BASH}" "${MODULE_DIR}/start.sh" "${FAKE_PROJECT}"

  assert_success
  # The helper writes its marker synchronously; the qmd work runs detached.
  run cat "${FAKE_PROJECT}/.agents/logs/qmd-index.log"
  assert_output --partial "reindex-memories-prune-start"

  local i
  for i in $(seq 1 50); do
    [[ "$(wc -l < "${call_log}" 2>/dev/null || echo 0)" -ge 2 ]] && break
    sleep 0.1
  done
  run cat "${call_log}"
  assert_line --index 0 "cleanup"
  assert_line --index 1 "update"

  rm -rf "${fake_qmd}" "${call_log}"
}
