#!/usr/bin/env bats
# =============================================================================
# bin/tests/sync_run_outputs_tests.bats
# Tests for the e2e launchers' host-side helpers in tests/test-project/
# test-lib.sh: reserve_audit_nn() and sync_run_outputs().
#
# The audit report used to be copied back from the run's isolated /app copy at
# launcher exit — too late while an interactive shell kept the launcher alive
# (the report sat in /tmp/devbot-test-* until the human copied it by hand). The
# launchers now bind-mount the fixture's thinking/ dir into the container, so
# the audit writes the report straight onto the fixture — which makes the report
# id a resource parallel runs share. reserve_audit_nn() claims it atomically and
# sync_run_outputs() only files LOGS (never copies, renames, or deletes a report).
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  LIB="${REPO_ROOT}/tests/test-project/test-lib.sh"

  SANDBOX="$(mktemp -d)"
  FIXTURE="${SANDBOX}/fixture"
  RUN_DIR="${SANDBOX}/run"
  THINKING="${FIXTURE}/.agents/memory/thinking"

  mkdir -p "${THINKING}" "${FIXTURE}/.agents/logs" "${RUN_DIR}/.agents/logs"

  # shellcheck source=/dev/null
  source "$LIB"
}

teardown() {
  rm -rf "$SANDBOX" 2>/dev/null || true
}

# ── reserve_audit_nn ──────────────────────────────────────────────────────────

@test "reserve_audit_nn: claims the next free id and creates its placeholder" {
  echo x > "${THINKING}/devbot-audit-05.md"
  run reserve_audit_nn "${THINKING}"
  assert_success
  assert_output "06"
  [[ -f "${THINKING}/devbot-audit-06.md" ]]
}

@test "reserve_audit_nn: successive claims do not collide" {
  run reserve_audit_nn "${THINKING}"
  assert_output "01"
  run reserve_audit_nn "${THINKING}"
  assert_output "02"
}

@test "reserve_audit_nn: ignores probe files that are not numeric reports" {
  : > "${THINKING}/devbot-audit-probe-20260927.md"
  run reserve_audit_nn "${THINKING}"
  assert_output "01"
}

# ── sync_run_outputs ──────────────────────────────────────────────────────────

@test "sync_run_outputs: files logs under the reserved report, never touching reports" {
  echo "old" > "${THINKING}/devbot-audit-66.md"
  echo "new" > "${THINKING}/devbot-audit-67.md"
  echo "log" > "${RUN_DIR}/.agents/logs/memory-index.log"

  run sync_run_outputs "${RUN_DIR}" "${FIXTURE}" "oc" "devbot-audit-67.md"

  assert_success
  assert_output --partial "report written via mount"
  [[ -f "${FIXTURE}/.agents/logs/devbot-audit-67/memory-index.log" ]]
  assert_equal "$(cat "${THINKING}/devbot-audit-66.md")" "old"
  assert_equal "$(cat "${THINKING}/devbot-audit-67.md")" "new"
  [[ ! -f "${THINKING}/devbot-audit-68.md" ]]
}

@test "sync_run_outputs: stages harness logs under the reserved report id" {
  echo "new" > "${THINKING}/devbot-audit-67.md"
  mkdir -p "${RUN_DIR}/.agents/logs/harness"
  echo "mcp" > "${RUN_DIR}/.agents/logs/harness/mcp-logs.jsonl"

  run sync_run_outputs "${RUN_DIR}" "${FIXTURE}" "oc" "devbot-audit-67.md"

  assert_success
  [[ -f "${FIXTURE}/.agents/logs/devbot-audit-67/harness/mcp-logs.jsonl" ]]
}

@test "sync_run_outputs: an unfilled reserved placeholder falls back to a timestamp label" {
  : > "${THINKING}/devbot-audit-07.md" # reserved but never written by the audit
  echo "log" > "${RUN_DIR}/.agents/logs/memory-index.log"

  run sync_run_outputs "${RUN_DIR}" "${FIXTURE}" "oc" "devbot-audit-07.md"

  assert_success
  assert_output --partial "WARN: no devbot-audit report"
  [[ ! -d "${FIXTURE}/.agents/logs/devbot-audit-07" ]]
  assert_equal "$(ls -d "${FIXTURE}"/.agents/logs/oc-* 2>/dev/null | wc -l)" "1"
}

@test "sync_run_outputs: no report and no logs → nothing filed, exits 0" {
  run sync_run_outputs "${RUN_DIR}" "${FIXTURE}" "oc" "devbot-audit-01.md"

  assert_success
  assert_equal "$(ls -A "${FIXTURE}/.agents/logs" | wc -l)" "0"
}

# ── launcher wiring ──────────────────────────────────────────────────────────

@test "launchers: mount the fixture thinking/ dir and pass the reserved id" {
  local launcher
  for launcher in test-oc.sh test-cc.sh; do
    run grep -qF '${SCRIPT_DIR}/.agents/memory/thinking:/app/.agents/memory/thinking' \
      "${REPO_ROOT}/tests/test-project/${launcher}"
    assert_success
    run grep -q 'DEVBOT_AUDIT_NN=' "${REPO_ROOT}/tests/test-project/${launcher}"
    assert_success
  done
}

@test "launchers: name the gateway root and the host project for the index hook" {
  # Without these the container's index hook resolves the container path against
  # a gateway rooted at the host's $HOME and skips every session (audit-70 FAIL).
  local launcher
  for launcher in test-oc.sh test-cc.sh; do
    run grep -q 'CODEBASE_MEMORY_ROOT=' "${REPO_ROOT}/tests/test-project/${launcher}"
    assert_success
    run grep -q 'CODEBASE_MEMORY_HOST_PROJECT=' "${REPO_ROOT}/tests/test-project/${launcher}"
    assert_success
  done
}

# ── run_dir_create / codebase_gateway_mount ──────────────────────────────────

@test "run_dir_create: builds the run copy under \$DEV_BOT_TEST_RUN_ROOT" {
  export DEV_BOT_TEST_RUN_ROOT="${SANDBOX}/runs"
  run run_dir_create "${FIXTURE}" "oc"
  assert_success
  local created="$output"
  [[ -d "${created}" ]]
  assert_equal "${created%/*}" "${DEV_BOT_TEST_RUN_ROOT}"
  run_dir_destroy "${created}"
  [[ ! -d "${created}" ]]
}

@test "run_dir_destroy: refuses to remove a path outside the run root" {
  export DEV_BOT_TEST_RUN_ROOT="${SANDBOX}/runs"
  mkdir -p "${SANDBOX}/keep"
  run_dir_destroy "${SANDBOX}/keep"
  [[ -d "${SANDBOX}/keep" ]]
}

@test "codebase_gateway_mount: reads the gateway's bind source" {
  local stub="${SANDBOX}/bin"
  mkdir -p "${stub}"
  printf '#!/usr/bin/env bash\necho "/host/root"\n' > "${stub}/docker"
  chmod +x "${stub}/docker"
  run env PATH="${stub}:${PATH}" bash -c "source '${LIB}'; codebase_gateway_mount"
  assert_success
  assert_output "/host/root"
}

@test "codebase_gateway_mount: falls back to \$HOME when the gateway is absent" {
  local stub="${SANDBOX}/bin2"
  mkdir -p "${stub}"
  printf '#!/usr/bin/env bash\nexit 1\n' > "${stub}/docker"
  chmod +x "${stub}/docker"
  run env PATH="${stub}:${PATH}" HOME="/fallback/home" bash -c "source '${LIB}'; codebase_gateway_mount"
  assert_success
  assert_output "/fallback/home"
}
