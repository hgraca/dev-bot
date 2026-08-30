#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/module_script_tests.bats
# Tests for _run_module_script, its wrappers, and _collect_module_scripts.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SANDBOX_DIR="$(mktemp -d)"

  command -v python3 &>/dev/null || skip "python3 not installed"

  export MOCK_DISABLED_MODULES="[]"
  export DEV_BOT_ROOT="${SANDBOX_DIR}"
}

teardown() {
  rm -rf "${SANDBOX_DIR}" 2>/dev/null || true
}

# ── Helpers ────────────────────────────────────────────────────────────────

# Source the real shared library, then override _devbot_get_disabled_modules
# with a mock that returns MOCK_DISABLED_MODULES.
_source_lib() {
  # shellcheck source=../functions.sh
  source "${PROJECT_ROOT}/src/_shared/functions.sh"

  # Override with test-controlled mock
  # shellcheck disable=SC2317
  _devbot_get_disabled_modules() {
    echo "${MOCK_DISABLED_MODULES:-[]}"
  }
}

# Create a module directory with an optional script.
# Usage: _add_module <base_dir> <name> [script_name] [script_body]
_add_module() {
  local base_dir="$1"
  local name="$2"
  local script_name="${3:-}"
  local script_body="${4:-exit 0}"

  local dir="${SANDBOX_DIR}/${base_dir}/${name}"
  mkdir -p "${dir}"

  if [[ -n "${script_name}" ]]; then
    cat > "${dir}/${script_name}" <<SCRIPT_EOF
#!/usr/bin/env bash
${script_body}
SCRIPT_EOF
    chmod +x "${dir}/${script_name}"
  fi
}

# Create a module with an init script that echoes received args.
_add_init_module() {
  local base_dir="$1"
  local name="$2"
  _add_module "${base_dir}" "${name}" "init.sh" 'echo "args: $*"'
}

# ── _run_module_script ─────────────────────────────────────────────────────

@test "runs script in each module that has it" {
  _source_lib
  _add_module "src/tools" "alpha" "install.sh" 'echo "alpha_ok"'
  _add_module "src/tools" "beta"  "install.sh" 'echo "beta_ok"'

  run _run_module_script "${SANDBOX_DIR}/src/tools" "install.sh" "Installing" "installed"
  assert_success
  assert_output --partial "alpha_ok"
  assert_output --partial "beta_ok"
}

@test "skips disabled modules" {
  _source_lib
  export MOCK_DISABLED_MODULES='["skip-me"]'
  _add_module "src/tools" "skip-me"  "install.sh" 'echo "should_not_run"'
  _add_module "src/tools" "keep-me"  "install.sh" 'echo "keep_ok"'

  run _run_module_script "${SANDBOX_DIR}/src/tools" "install.sh" "Installing" "installed"
  assert_success
  refute_output --partial "should_not_run"
  assert_output --partial "keep_ok"
  assert_output --partial "skip-me: disabled per config"
}

@test "skips modules without the script" {
  _source_lib
  _add_module "src/tools" "has-script"    "install.sh" 'echo "has_ok"'
  _add_module "src/tools" "no-script"     ""  # no install.sh

  run _run_module_script "${SANDBOX_DIR}/src/tools" "install.sh" "Installing" "installed"
  assert_success
  assert_output --partial "has_ok"
  refute_output --partial "no-script"
}

@test "passes extra args to each script" {
  _source_lib
  _add_init_module "src/tools" "mod-a"

  run _run_module_script "${SANDBOX_DIR}/src/tools" "init.sh" "Initializing" "initialized" "/fake/project"
  assert_success
  assert_output --partial "args: /fake/project"
}

@test "handles script failure gracefully and continues" {
  _source_lib
  _add_module "src/tools" "failer"  "install.sh" 'echo "failer_ran"; exit 1'
  _add_module "src/tools" "survivor" "install.sh" 'echo "survivor_ok"'

  run _run_module_script "${SANDBOX_DIR}/src/tools" "install.sh" "Installing" "installed"
  assert_success
  assert_output --partial "failer_ran"
  assert_output --partial "survivor_ok"
  assert_output --partial "failed"
}

@test "exports MODULE_SCRIPT_COUNT for successful runs" {
  _source_lib
  _add_module "src/tools" "a" "install.sh"
  _add_module "src/tools" "b" "install.sh"

  _run_module_script "${SANDBOX_DIR}/src/tools" "install.sh" "Installing" "installed" >/dev/null
  [ "${MODULE_SCRIPT_COUNT}" = "2" ]
}

@test "exports MODULE_SCRIPT_FAILED for failures" {
  _source_lib
  _add_module "src/tools" "a" "install.sh" 'exit 1'

  _run_module_script "${SANDBOX_DIR}/src/tools" "install.sh" "Installing" "installed" >/dev/null
  [ "${MODULE_SCRIPT_FAILED}" = "1" ]
  [ "${MODULE_SCRIPT_COUNT}" = "0" ]
}

@test "reports ok when no scripts found" {
  _source_lib
  # base dir with no subdirectories at all
  mkdir -p "${SANDBOX_DIR}/src/tools/empty-dir"

  run _run_module_script "${SANDBOX_DIR}/src/tools" "install.sh" "Installing" "installed"
  assert_success
  assert_output --partial "No install.sh scripts found"
}

@test "works with agentic modules path" {
  _source_lib
  _add_module "src/agentic" "mod-x" "update.sh" 'echo "agentic_ok"'

  run _run_module_script "${SANDBOX_DIR}/src/agentic" "update.sh" "Updating" "updated"
  assert_success
  assert_output --partial "agentic_ok"
}

# ── Wrapper: _install_modules ──────────────────────────────────────────────

@test "_install_modules calls install.sh with correct labels" {
  _source_lib
  _add_module "src/tools" "pkg" "install.sh" 'echo "installed"'

  run _install_modules "${SANDBOX_DIR}/src/tools"
  assert_success
  assert_output --partial "Installing pkg"
  assert_output --partial "pkg installed"
}

# ── Wrapper: _update_modules ───────────────────────────────────────────────

@test "_update_modules calls update.sh with correct labels" {
  _source_lib
  _add_module "src/tools" "pkg" "update.sh" 'echo "updated"'

  run _update_modules "${SANDBOX_DIR}/src/tools"
  assert_success
  assert_output --partial "Updating pkg"
  assert_output --partial "pkg updated"
}

# ── Wrapper: _init_modules ─────────────────────────────────────────────────

@test "_init_modules passes extra args through" {
  _source_lib
  _add_init_module "src/tools" "pkg"

  run _init_modules "${SANDBOX_DIR}/src/tools" "/my/project"
  assert_success
  assert_output --partial "Initializing pkg"
  assert_output --partial "args: /my/project"
}

# ── Wrapper: _uninstall_modules ────────────────────────────────────────────

@test "_uninstall_modules calls uninstall.sh with correct labels" {
  _source_lib
  _add_module "src/tools" "pkg" "uninstall.sh" 'echo "uninstalled"'

  run _uninstall_modules "${SANDBOX_DIR}/src/tools"
  assert_success
  assert_output --partial "Uninstalling pkg"
  assert_output --partial "pkg uninstalled"
}

# ── _collect_module_scripts ────────────────────────────────────────────────

@test "collects executable scripts from multiple base dirs" {
  _source_lib
  _add_module "src/tools"   "tool-a" "reset.sh" 'echo "a"'
  _add_module "src/agentic" "mod-b"  "reset.sh" 'echo "b"'

  run _collect_module_scripts "reset.sh" \
    "${SANDBOX_DIR}/src/tools" \
    "${SANDBOX_DIR}/src/agentic"

  assert_success
  assert_output --partial "/tool-a/"
  assert_output --partial "/mod-b/"
  # Exactly 2 lines
  [ "$(echo "${output}" | wc -l)" = "2" ]
}

@test "skips non-executable files" {
  _source_lib
  _add_module "src/tools" "mod-a" "reset.sh"
  # Make it non-executable
  chmod -x "${SANDBOX_DIR}/src/tools/mod-a/reset.sh"

  run _collect_module_scripts "reset.sh" "${SANDBOX_DIR}/src/tools"
  assert_success
  [ -z "${output}" ]
}

@test "returns empty when no matching scripts" {
  _source_lib
  mkdir -p "${SANDBOX_DIR}/src/tools/empty"

  run _collect_module_scripts "reset.sh" "${SANDBOX_DIR}/src/tools"
  assert_success
  [ -z "${output}" ]
}
