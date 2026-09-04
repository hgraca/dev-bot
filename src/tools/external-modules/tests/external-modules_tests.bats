#!/usr/bin/env bats
# =============================================================================
# src/tools/external-modules/tests/external-modules_tests.bats
# Tests for the external modules manager.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

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
  echo '{"external_modules":{}}' > "${DEV_BOT_ROOT}/.devbot.jsonc"

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
  echo '{"external_modules":{}}' > "$tmp_config"

  run bash "$TOOL" list
  assert_success
  assert_output --partial "Add one: devbot module add <git-url>"
}

# ── _ensure_config stdout leak (audit-32 NOTE) ───────────────────────────────

@test "commands with an existing modules config do not dump raw JSON to stdout" {
  # Regression: _ensure_config probed the config with read_jsonc.py and only
  # silenced stderr, so the raw external_modules JSON printed to stdout on
  # every module command whose config already had the key.
  local config="${DEV_BOT_ROOT}/.devbot.global.jsonc"
  cat > "$config" <<'JSON'
{
  "external_modules": {
    "demo-module": {
      "url": "https://example.com/demo.git",
      "paths": { "skills": "./skills" }
    }
  }
}
JSON

  # `list` calls _ensure_config first — with the key present, the probe's
  # stdout must not leak into the command output.
  run bash "$TOOL" list

  assert_success
  assert_output --partial "demo-module"
  refute_output --partial '"external_modules"'
  refute_output --partial 'https://example.com/demo.git'
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

@test "init: wires a config-only local module (CLI-registered, not declared)" {
  local loc_dir="${TEST_HOME}/dummy-mod"
  mkdir -p "${loc_dir}/skills"
  echo "skill" > "${loc_dir}/skills/x.md"

  export CONFIG_FILE="${DEV_BOT_ROOT}/.devbot.global.jsonc"
  export MODULES_DIR="${DEV_BOT_ROOT}/vendor"
  mkdir -p "${DEV_BOT_ROOT}/src/agentic" "${DEV_BOT_ROOT}/src/tools"

  cat > "${CONFIG_FILE}" <<EOF
{
  "external_modules": {
    "dummy": { "local_path": "${loc_dir}", "paths": { "skills": "skills" } }
  }
}
EOF

  local project="${TEST_HOME}/proj"
  mkdir -p "${project}"

  run bash "${MODULE_DIR}/init.sh" "${project}"

  assert_success
  assert_output --partial "wiring complete"
  # Config-only entries are wired into the devbot dir like declared ones
  # (audit-29 FAIL-1): .agents link + storage mirror.
  assert [ -L "${project}/.agents/skills/dummy" ]
  assert [ "$(readlink "${project}/.agents/skills/dummy")" = "${loc_dir}/skills" ]
  assert [ -e "${project}/.agents/skills/dummy/x.md" ]
  assert [ -L "${DEV_BOT_ROOT}/storage/external-agentic-modules/dummy/skills" ]
}

@test "init: does not wire entries declared by a disabled module" {
  # react/svelte declare mindrally-* entries while disabled — the config-only
  # pass must not pull them into .agents (module-managed, intentionally off).
  local loc_dir="${TEST_HOME}/offdecl-mod"
  mkdir -p "${loc_dir}/skills"
  echo "skill" > "${loc_dir}/skills/x.md"

  export CONFIG_FILE="${DEV_BOT_ROOT}/.devbot.global.jsonc"
  export MODULES_DIR="${DEV_BOT_ROOT}/vendor"
  mkdir -p "${DEV_BOT_ROOT}/src/agentic/offmod"
  cat > "${DEV_BOT_ROOT}/src/agentic/offmod/external-modules.json" <<'EOF'
{
  "offdecl": { "url": "https://example.com/off/decl.git", "paths": { "skills": "skills" } }
}
EOF

  cat > "${CONFIG_FILE}" <<EOF
{
  "modules": { "offmod": false },
  "external_modules": {
    "offdecl": { "local_path": "${loc_dir}", "paths": { "skills": "skills" } }
  }
}
EOF

  local project="${TEST_HOME}/proj-off"
  mkdir -p "${project}"

  run bash "${MODULE_DIR}/init.sh" "${project}"

  assert_success
  assert_output --partial "declared by a module"
  assert [ ! -e "${project}/.agents/skills/offdecl" ]
}

@test "remove: cleans .agents links in projects from the global projects registry" {
  local loc_dir="${TEST_HOME}/dummy-mod"
  mkdir -p "${loc_dir}/skills"
  echo "skill" > "${loc_dir}/skills/x.md"

  export CONFIG_FILE="${DEV_BOT_ROOT}/.devbot.global.jsonc"
  export MODULES_DIR="${DEV_BOT_ROOT}/vendor"
  mkdir -p "${DEV_BOT_ROOT}/src/agentic" "${DEV_BOT_ROOT}/src/tools"

  # The project lives OUTSIDE DEV_BOT_ROOT and is known only through the
  # global config's projects registry (audit-29 FAIL-2).
  local project="${TEST_HOME}/outside-proj"
  mkdir -p "${project}"

  cat > "${CONFIG_FILE}" <<EOF
{
  "projects": ["${project}"],
  "external_modules": {
    "dummy": { "local_path": "${loc_dir}", "paths": { "skills": "skills" } }
  }
}
EOF

  run bash "${MODULE_DIR}/init.sh" "${project}"
  assert_success
  assert [ -L "${project}/.agents/skills/dummy" ]

  run bash "$TOOL" remove dummy

  assert_success
  assert_output --partial "Unregistered: dummy"
  # _unwire_module now removes .agents links too (audit-29 NOTE-1), reaching
  # the project through the global projects registry (audit-29 FAIL-2).
  assert [ ! -e "${project}/.agents/skills/dummy" ]
  assert [ ! -e "${DEV_BOT_ROOT}/storage/external-agentic-modules/dummy" ]
}

@test "remove: cleans the flattened .claude/skills entry left dangling under claudecode" {
  # audit-31 §9: under the claudecode harness, _link_claude_skills_flat links
  # an external module's SKILL.md into .claude/skills/<frontmatter-name>/ as a
  # symlink into the module's storage mirror. `module remove` deleted the
  # mirror but not the flattened symlink — which then dangled (its target was
  # gone). Reinit's broken-symlink sweep only scans .agents/, so the dangling
  # entry survived future reinits.
  local loc_dir="${TEST_HOME}/dummy-mod"
  mkdir -p "${loc_dir}/skills"
  printf '%s\n' "---" "name: dummy-skill" "---" "" "# Dummy skill" \
    > "${loc_dir}/skills/SKILL.md"

  export CONFIG_FILE="${DEV_BOT_ROOT}/.devbot.global.jsonc"
  export MODULES_DIR="${DEV_BOT_ROOT}/vendor"
  mkdir -p "${DEV_BOT_ROOT}/src/agentic" "${DEV_BOT_ROOT}/src/tools"

  local project="${TEST_HOME}/claude-proj"
  mkdir -p "${project}/.claude"

  cat > "${CONFIG_FILE}" <<EOF
{
  "projects": ["${project}"],
  "external_modules": {
    "dummy": { "local_path": "${loc_dir}", "paths": { "skills": "skills" } }
  }
}
EOF

  run bash "${MODULE_DIR}/init.sh" "${project}"
  assert_success
  assert [ -L "${project}/.agents/skills/dummy" ]

  # Simulate what the claudecode harness flatten does: a symlinked SKILL.md
  # pointing into the module's storage mirror.
  local storage_mirror="${DEV_BOT_ROOT}/storage/external-agentic-modules/dummy"
  assert [ -d "${storage_mirror}" ]
  local flat_skill="${project}/.claude/skills/dummy-skill"
  mkdir -p "${flat_skill}"
  ln -s "${storage_mirror}/skills/SKILL.md" "${flat_skill}/SKILL.md"
  assert [ -e "${flat_skill}/SKILL.md" ]

  run bash "$TOOL" remove dummy

  assert_success
  assert_output --partial "Unregistered: dummy"
  # The flattened claudecode entry is gone — not left dangling.
  assert [ ! -e "${flat_skill}/SKILL.md" ]
  assert [ ! -e "${flat_skill}" ]
  # And the mirror + .agents link are cleaned as before.
  assert [ ! -e "${DEV_BOT_ROOT}/storage/external-agentic-modules/dummy" ]
  assert [ ! -e "${project}/.agents/skills/dummy" ]
}

@test "add --help prints usage instead of treating --help as a module path (audit-45 §9)" {
  # audit-45 §9 NOTE: `module add --help` used to fall through to the
  # positional <url|path> branch and attempt `git clone ... --help`.
  run bash "$TOOL" add --help

  assert_success
  assert_output --partial "Usage: devbot module add <url|path>"
  refute_output --partial "Cloning"
  refute_output --partial "clone"
  # Nothing registered, nothing cloned into vendor/.
  assert [ ! -e "${DEV_BOT_ROOT}/vendor/--help" ]
}
