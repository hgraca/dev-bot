#!/usr/bin/env bats
# =============================================================================
# bin/tests/up_config_baseline_tests.bats
#
# The start order is: auto-update → (config changed? reinit → init.sh writes the
# wiring baseline) → up.sh → harness. up.sh then REWRITES the global config
# (`_rebuild_external_module_config` merges the external-module declarations), so
# without a refresh the baseline written by init.sh is immediately stale and the
# NEXT start re-detects "config changed" and reinits again (audit-71 C2).
#
# These tests do NOT require a Docker daemon: only `_rebuild_external_module_config`
# is exercised, with the merge stubbed to mutate the global config.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SANDBOX="$(mktemp -d)"

  command -v python3 &>/dev/null || skip "python3 not installed"

  mkdir -p "${SANDBOX}/bin" "${SANDBOX}/src/_shared"
  # Production up.sh, trailing `main "$@"` stripped so sourcing it does nothing.
  sed '/^main "\$@"/d' "${PROJECT_ROOT}/bin/up.sh" > "${SANDBOX}/bin/up.sh"

  # Output helpers up.sh calls on the way in, plus the one helper it invokes at
  # source time (`_devbot_codebase_memory_root`).
  cat > "${SANDBOX}/src/_shared/functions.sh" <<'STUB'
#!/usr/bin/env bash
_header_1() { true; }
_header_2() { true; }
_header_3() { true; }
_info() { true; }
_ok()   { true; }
_skip() { true; }
_warn() { true; }
_log()  { true; }
_error() { echo "ERROR: $*" >&2; }
_fatal() { echo "FATAL: $*" >&2; exit 1; }
_fmt_duration() { echo "0s"; }
_devbot_codebase_memory_root() { echo "$HOME"; }
STUB

  # The REAL baseline helpers under test — extracted verbatim so the stub can
  # never drift from production behaviour.
  {
    awk '/^_devbot_config_sha_path\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh"
    awk '/^_devbot_config_sha\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh"
    awk '/^_devbot_wiring_sha\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh"
    awk '/^_devbot_config_changed\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh"
    awk '/^_devbot_write_config_sha\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh"
  } >> "${SANDBOX}/src/_shared/functions.sh"

  printf '{}\n' > "${SANDBOX}/.devbot.global.jsonc"
  printf '{}\n' > "${SANDBOX}/.devbot.project.jsonc"
  # The post-merge global config the stubbed merge copies in.
  printf '{"external_modules": {"x": {"url": "u"}}}\n' > "${SANDBOX}/mutated.json"
}

teardown() {
  rm -rf "${SANDBOX}"
}

# Run a snippet in a subshell that has sourced the sandbox up.sh from the sandbox
# cwd (so PROJECT_DIR/DEV_BOT_ROOT resolve to the sandbox). env-passed, so the
# snippet is evaluated by the inner shell — quotes and `$SANDBOX` stay intact.
_sandbox_bash() {
  SANDBOX="${SANDBOX}" SNIPPET="$1" bash -c '
    cd "$SANDBOX" || exit 1
    source ./bin/up.sh
    eval "$SNIPPET"
  '
}

@test "the external-module config merge refreshes the wiring baseline (audit-71 C2)" {
  # Baseline matches the pre-merge configs — the state init.sh leaves behind.
  _sandbox_bash '_devbot_write_config_sha "$SANDBOX"' >/dev/null 2>&1 || true
  run _sandbox_bash '_devbot_config_changed "$SANDBOX"'
  assert_failure   # unchanged (return 1) before the merge mutates anything

  # The merge mutates the shared global config, exactly as up.sh does per start.
  run _sandbox_bash '_devbot_rebuild_external_module_config() { cp "$SANDBOX/mutated.json" "$DEV_BOT_ROOT/.devbot.global.jsonc"; }; _rebuild_external_module_config'
  assert_success

  # Without the refresh the baseline is now stale → the next start would reinit
  # again. With it, the baseline tracks the post-merge config.
  run _sandbox_bash '_devbot_config_changed "$SANDBOX"'
  assert_failure
}

@test "a merge that changes nothing leaves the baseline valid" {
  _sandbox_bash '_devbot_write_config_sha "$SANDBOX"' >/dev/null 2>&1 || true

  run _sandbox_bash '_devbot_rebuild_external_module_config() { true; }; _rebuild_external_module_config'
  assert_success

  run _sandbox_bash '_devbot_config_changed "$SANDBOX"'
  assert_failure
}

@test "a pending (dirty) baseline is not consumed by a standalone merge (audit-71 C2/review)" {
  # Clean baseline, then the project config changes → a reinit is pending.
  _sandbox_bash '_devbot_write_config_sha "$SANDBOX"' >/dev/null 2>&1 || true
  printf '{"project_name": "edited"}\n' > "${SANDBOX}/.devbot.project.jsonc"

  run _sandbox_bash '_devbot_rebuild_external_module_config() { true; }; _rebuild_external_module_config'
  assert_success

  # A standalone `devbot up` / `make up` must NOT write the baseline and erase
  # the pending reinit — only a start flow that already reinited may refresh it.
  run _sandbox_bash '_devbot_config_changed "$SANDBOX"'
  assert_success
}
