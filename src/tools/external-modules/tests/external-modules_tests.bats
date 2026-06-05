#!/usr/bin/env bats
# =============================================================================
# src/tools/external-modules/tests/external-modules_tests.bats
# Tests for the external modules manager.
# =============================================================================

setup() {
  load "$(npm root -g)/bats-support/load.bash"
  load "$(npm root -g)/bats-assert/load.bash"

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  TOOL="$MODULE_DIR/tools/module.sh"

  # Create a temporary directory for the test's devbot root
  TEST_HOME="$(mktemp -d)"
  export TEST_HOME
  DEV_BOT_ROOT="${TEST_HOME}/devbot"
  export DEV_BOT_ROOT
  mkdir -p "${DEV_BOT_ROOT}"
  # Initialize a clean .devbot.jsonc
  echo '{"modules":{}}' > "${DEV_BOT_ROOT}/.devbot.jsonc"

  # Create a minimal devbot binary for testing the module subcommand
  mkdir -p "${DEV_BOT_ROOT}/bin"
  cat > "${DEV_BOT_ROOT}/bin/devbot" <<'DEVBOT_EOF'
#!/usr/bin/env bash
if [[ "$1" == "module" && "$2" == "help" ]]; then
  echo "Usage: devbot module <subcommand>"
  echo ""
  echo "Subcommands:"
  echo "  install    Clone/pull configured external modules"
  echo "  init [path] Wire modules into .opencode/ directories"
  echo "  add <url|path>   Register a module (git URL or local path)"
  echo "  remove <name>    Unregister a module"
  echo "  list              List registered modules"
  echo "  sync [--project=<dir>]  Re-wire all modules (alias for init)"
  exit 0
fi
echo "Unknown command: $1"
exit 1
DEVBOT_EOF
  chmod +x "${DEV_BOT_ROOT}/bin/devbot"

  command -v python3 &>/dev/null || skip "python3 not installed"
  command -v git &>/dev/null || skip "git not installed"
}

teardown() {
  rm -rf "$TEST_HOME" 2>/dev/null || true
}

# ── Help ───────────────────────────────────────────────────────────────────────

@test "help: shows usage with no args" {
  run bash "$TOOL"

  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "add"
  assert_output --partial "remove"
  assert_output --partial "list"
  assert_output --partial "sync"
}

@test "help: --help flag shows usage" {
  run bash "$TOOL" --help

  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "add"
}

# ── List (empty) ──────────────────────────────────────────────────────────────

@test "list: shows empty state when no modules" {
  # Use a temp config to avoid polluting real devbot config
  local tmp_config="${DEV_BOT_ROOT}/.devbot.jsonc"
  echo '{"modules":{}}' > "$tmp_config"

  run bash "$TOOL" list
  assert_success
  assert_output --partial "Add one: devbot module add <git-url>"
}

# ── Add local module ──────────────────────────────────────────────────────────

@test "add: local directory registers as module" {
  local mod_dir="${TEST_HOME}/test-module"
  mkdir -p "${mod_dir}/skills" "${mod_dir}/agents"
  echo "test skill" > "${mod_dir}/skills/test.md"

  run bash "$TOOL" add "${mod_dir}" --name=test-module

  assert_success
  assert_output --partial "Registered: test-module"
}

@test "add: duplicate module reports already registered" {
  local mod_dir="${TEST_HOME}/dup-module"
  mkdir -p "${mod_dir}/skills"

  # First add
  bash "$TOOL" add "${mod_dir}" --name=dup-module 2>/dev/null || true
  # Second add — should detect duplicate
  run bash "$TOOL" add "${mod_dir}" --name=dup-module

  assert_success
  assert_output --partial "Already registered"
}

# ── Remove ────────────────────────────────────────────────────────────────────

@test "remove: unknown module shows warning" {
  run bash "$TOOL" remove nonexistent

  assert_success
  assert_output --partial "not found"
}

# ── Unknown subcommand ─────────────────────────────────────────────────────────

@test "unknown subcommand: error message" {
  run bash "$TOOL" foobar

  assert_failure
  assert_output --partial "Unknown"
}

# ── devbot integration ────────────────────────────────────────────────────────

@test "devbot module subcommand exists" {
    run bash "${DEV_BOT_ROOT}/bin/devbot" module help

    assert_success
    assert_output --partial "Usage:"
    assert_output --partial "install"
    assert_output --partial "init"
    assert_output --partial "add"
    assert_output --partial "remove"
    assert_output --partial "list"
    assert_output --partial "sync"
}

# ── Storage structure (Task 1) ──────────────────────────────────────────────────

@test "storage: creates directory symlinks for string-valued paths" {
  # Source the functions to get _setup_external_module_storage
  source "${MODULE_DIR}/functions.sh"

  local module_name="test-string-module"
  local src_dir="${TEST_HOME}/vendor/test-org/test-repo"
  local storage_base="${DEV_BOT_ROOT}/storage/external-agentic-modules/${module_name}"
  local paths_json='{"skills":"skills","agents":"agents"}'

  # Create source directories with distinctive content
  mkdir -p "${src_dir}/skills" "${src_dir}/agents"
  echo "skill1" > "${src_dir}/skills/skill-a.md"
  echo "agent1" > "${src_dir}/agents/agent-a.md"

  # Run the function
  run _setup_external_module_storage "${src_dir}" "${module_name}" "${paths_json}" "${DEV_BOT_ROOT}"

  assert_success

  # Verify directory symlinks exist
  assert [ -L "${storage_base}/skills" ]
  assert [ -L "${storage_base}/agents" ]

  # Verify they resolve to the correct paths
  assert [ "$(readlink "${storage_base}/skills")" = "${src_dir}/skills" ]
  assert [ "$(readlink "${storage_base}/agents")" = "${src_dir}/agents" ]

  # Verify content accessible through symlinks
  assert [ -f "${storage_base}/skills/skill-a.md" ]
  assert [ -f "${storage_base}/agents/agent-a.md" ]

  # Cleanup
  rm -rf "${DEV_BOT_ROOT}/storage"
}

@test "storage: creates file symlinks for object-valued paths" {
  source "${MODULE_DIR}/functions.sh"

  local module_name="test-object-module"
  local src_dir="${TEST_HOME}/vendor/test-org/test-repo"
  local storage_base="${DEV_BOT_ROOT}/storage/external-agentic-modules/${module_name}"
  local paths_json='{"memory":{"CLAUDE.md":"active/instructions.md"}}'

  # Create source file
  mkdir -p "${src_dir}"
  echo "# Instructions" > "${src_dir}/CLAUDE.md"

  # Run the function
  run _setup_external_module_storage "${src_dir}" "${module_name}" "${paths_json}" "${DEV_BOT_ROOT}"

  assert_success

  # Verify file-level symlink at nested path
  assert [ -L "${storage_base}/memory/active/instructions.md" ]

  # Verify content accessible
  assert [ -f "${storage_base}/memory/active/instructions.md" ]
  run cat "${storage_base}/memory/active/instructions.md"
  assert_output --partial "Instructions"

  # Cleanup
  rm -rf "${DEV_BOT_ROOT}/storage"
}

@test "storage: idempotent — re-running skips existing correct symlinks" {
  source "${MODULE_DIR}/functions.sh"

  local module_name="test-idempotent"
  local src_dir="${TEST_HOME}/vendor/test-org/test-repo"
  local storage_base="${DEV_BOT_ROOT}/storage/external-agentic-modules/${module_name}"
  local paths_json='{"skills":"skills"}'

  mkdir -p "${src_dir}/skills"
  echo "content" > "${src_dir}/skills/test.md"

  # First run
  run _setup_external_module_storage "${src_dir}" "${module_name}" "${paths_json}" "${DEV_BOT_ROOT}"
  assert_success

  # Second run — should say "already correct"
  run _setup_external_module_storage "${src_dir}" "${module_name}" "${paths_json}" "${DEV_BOT_ROOT}"
  assert_success
  assert_output --partial "already correct"

  # Cleanup
  rm -rf "${DEV_BOT_ROOT}/storage"
}

@test "storage: mixed string and object paths in single module" {
  source "${MODULE_DIR}/functions.sh"

  local module_name="test-mixed"
  local src_dir="${TEST_HOME}/vendor/test-org/test-repo"
  local storage_base="${DEV_BOT_ROOT}/storage/external-agentic-modules/${module_name}"
  local paths_json='{"agents":"agents","memory":{"README.md":"docs/readme.md"}}'

  mkdir -p "${src_dir}/agents"
  echo "agent" > "${src_dir}/agents/a.md"
  echo "# Readme" > "${src_dir}/README.md"

  run _setup_external_module_storage "${src_dir}" "${module_name}" "${paths_json}" "${DEV_BOT_ROOT}"
  assert_success

  assert [ -L "${storage_base}/agents" ]
  assert [ -L "${storage_base}/memory/docs/readme.md" ]

  rm -rf "${DEV_BOT_ROOT}/storage"
}

@test "storage: warns when source directory does not exist" {
  source "${MODULE_DIR}/functions.sh"

  local module_name="test-missing-src"
  local src_dir="${TEST_HOME}/vendor/test-org/missing-repo"
  local paths_json='{"skills":"skills"}'

  mkdir -p "${TEST_HOME}/vendor/test-org/missing-repo"
  # Don't create skills/ subdir

  run _setup_external_module_storage "${src_dir}" "${module_name}" "${paths_json}" "${DEV_BOT_ROOT}"

  assert_success
  assert_output --partial "source dir not found"

  rm -rf "${DEV_BOT_ROOT}/storage"
}
