#!/usr/bin/env bats
# =============================================================================
# bin/tests/init_dirty_flag_tests.bats
#
# `.devbot.project.sha` is the per-project wiring baseline, and a MISSING
# baseline is the documented "needs reinit" state. The reset path therefore
# clears it BEFORE it touches the tree and only restores it when the wiring
# completes — so an interrupted run leaves the flag cleared and the next
# `devbot` start re-detects the change and repairs the wiring (audit-71 C3).
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SANDBOX="$(mktemp -d)"
  PROJECT="$(mktemp -d)"

  command -v python3 &>/dev/null || skip "python3 not installed"

  mkdir -p "${SANDBOX}/bin" "${SANDBOX}/src/_shared"
  # Production init.sh under a non-colliding name, `main "$@"` stripped so the
  # test can source it. It resolves DEV_BOT_ROOT to $SANDBOX from its own path.
  sed '/^main "\$@"/d' "${PROJECT_ROOT}/bin/init.sh" > "${SANDBOX}/bin/init-flow.sh"
  cp "${PROJECT_ROOT}/src/_shared/read_jsonc.py" \
    "${PROJECT_ROOT}/src/_shared/migrate_workspace_config.py" \
    "${SANDBOX}/src/_shared/"

  # The wiring child `_wire_project` spawns. Completes (writes the baseline)
  # only when INIT_COMPLETES=1; otherwise exits non-zero without writing —
  # the same shape a real interrupted wiring has.
  cat > "${SANDBOX}/bin/init.sh" <<'WIRE'
#!/usr/bin/env bash
source "${DEV_BOT_ROOT}/src/_shared/functions.sh"
if [[ "${INIT_COMPLETES:-0}" == "1" ]]; then
  _devbot_write_config_sha "$1"
  exit 0
fi
exit 1
WIRE
  chmod +x "${SANDBOX}/bin/init.sh"

  # Output helpers, plus the REAL baseline and containment helpers under test —
  # extracted verbatim so the stub cannot drift from production behaviour.
  cat > "${SANDBOX}/src/_shared/functions.sh" <<'STUB'
#!/usr/bin/env bash
_header_1() { true; }
_header_2() { echo "$*"; }
_header_3() { true; }
_info() { echo "INFO: $*"; }
_ok() { true; }
_skip() { true; }
_warn() { true; }
_log() { true; }
_step() { true; }
_error() { echo "ERROR: $*" >&2; }
_fatal() { echo "FATAL: $*" >&2; exit 1; }
_fmt_duration() { echo "0s"; }
_collect_module_scripts() { true; }
_get_projects() { echo '[]'; }
_devbot_get_disabled_modules() { echo '[]'; }
_devbot_get_project_dir() { echo ".agents"; }
_devbot_get_external_modules() { true; }
_devbot_disabled_external_names() { true; }
TEXT_BOLD=''; TEXT_BLUE=''; TEXT_CLEAR=''; TEXT_DIM=''
TEXT_GREEN=''; TEXT_YELLOW=''; TEXT_ORANGE=''; TEXT_RED=''
STUB
  {
    awk '/^_devbot_global_config\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh"
    awk '/^_devbot_config_sha_path\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh"
    awk '/^_devbot_config_sha\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh"
    awk '/^_devbot_wiring_sha\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh"
    awk '/^_devbot_config_changed\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh"
    awk '/^_devbot_write_config_sha\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh"
    awk '/^_devbot_clear_config_sha\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh"
    awk '/^_devbot_is_plain_relative_path\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh"
    awk '/^_devbot_module_memory_path\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh"
    awk '/^_devbot_project_initialized\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh"
    awk '/^_migrate_workspace_config\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh"
  } >> "${SANDBOX}/src/_shared/functions.sh"

  printf '{}\n' > "${SANDBOX}/.devbot.global.jsonc"
  printf '{"project_name": "demo"}\n' > "${PROJECT}/.devbot.project.jsonc"

  # Fake reset script: records whether the baseline exists DURING the reset.
  cat > "${SANDBOX}/reset-record.sh" <<RECORD
#!/usr/bin/env bash
if [[ -f "\${1}/.devbot.project.sha" ]]; then
  echo "baseline-present" > "${SANDBOX}/reset-saw-baseline"
else
  echo "baseline-absent" > "${SANDBOX}/reset-saw-baseline"
fi
RECORD
  chmod +x "${SANDBOX}/reset-record.sh"
}

teardown() {
  rm -rf "${SANDBOX}" "${PROJECT}" 2>/dev/null || true
}

# Run a snippet in a subshell that has sourced the sandboxed init flow from the
# sandbox cwd. env-passed, so the snippet is evaluated by the inner shell.
_sandbox_bash() {
  SANDBOX="${SANDBOX}" PROJECT="${PROJECT}" SNIPPET="$1" bash -c '
    export DEV_BOT_ROOT="$SANDBOX"
    cd "$SANDBOX" || exit 1
    source ./bin/init-flow.sh
    eval "$SNIPPET"
  '
}

@test "the reset path clears the baseline before the reset scripts run" {
  _sandbox_bash '_devbot_write_config_sha "$PROJECT"' >/dev/null 2>&1 || true
  run _sandbox_bash '_devbot_config_changed "$PROJECT"'
  assert_failure   # clean before the reset path

  run _sandbox_bash 'export INIT_COMPLETES=1; _reinit_project "$PROJECT" "$SANDBOX/reset-record.sh"'

  # The reset observed the cleared baseline — the dirty flag is set before the
  # tree is touched.
  run cat "${SANDBOX}/reset-saw-baseline"
  assert_output "baseline-absent"
}

@test "a reset path that fails leaves the baseline cleared, so the next start retries" {
  _sandbox_bash '_devbot_write_config_sha "$PROJECT"' >/dev/null 2>&1 || true

  run _sandbox_bash '_reinit_project "$PROJECT" "$SANDBOX/reset-record.sh"'

  # The wiring never completed → the baseline is still missing → init pending.
  run _sandbox_bash '_devbot_config_changed "$PROJECT"'
  assert_success
}

@test "a reset path that completes restores the baseline" {
  _sandbox_bash '_devbot_write_config_sha "$PROJECT"' >/dev/null 2>&1 || true

  run _sandbox_bash 'export INIT_COMPLETES=1; _reinit_project "$PROJECT" "$SANDBOX/reset-record.sh"'

  run _sandbox_bash '_devbot_config_changed "$PROJECT"'
  assert_failure   # restored → clean
}

# ── Wiring failure must propagate (review Finding 1) ───────────────────────
# If the reset path swallows a wiring failure, init still exits 0, so the
# auto-reinit caller reads it as success and the start continues on half-built
# wiring — defeating the abort and looping on the next start.

@test "init reports failure when the wiring fails" {
  _sandbox_bash '_devbot_write_config_sha "$PROJECT"' >/dev/null 2>&1 || true

  run _sandbox_bash '_reinit_project "$PROJECT" "$SANDBOX/reset-record.sh"'
  assert_failure
}

@test "init main exits non-zero and omits the success banner when the wiring fails" {
  run _sandbox_bash 'main'
  assert_failure
  refute_output --partial "DevBot init complete"
}
