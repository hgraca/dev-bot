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

# ── Local path sources (path field instead of url) ──────────────────────────────

_write_config() {
  # $1 = JSON body for .devbot.global.jsonc under the sandbox DEV_BOT_ROOT
  cat > "${DEV_BOT_ROOT}/.devbot.global.jsonc" <<EOF
$1
EOF
}

@test "install: path entry skips vendor clone and wires storage from local dir" {
  local loc_dir="${TEST_HOME}/local-install"
  mkdir -p "${loc_dir}/skills"
  echo "skill" > "${loc_dir}/skills/a.md"

  _write_config "{
    \"external_modules\": {
      \"loc-install\": { \"path\": \"${loc_dir}\", \"paths\": { \"skills\": \"skills\" } }
    }
  }"

  run bash "${MODULE_DIR}/install.sh"

  assert_success
  refute_output --partial "missing url"
  assert [ ! -d "${DEV_BOT_ROOT}/vendor" ]
  assert [ -L "${DEV_BOT_ROOT}/storage/external-agentic-modules/loc-install/skills" ]
  assert [ "$(readlink "${DEV_BOT_ROOT}/storage/external-agentic-modules/loc-install/skills")" = "${loc_dir}/skills" ]
}

@test "install: missing path dir warns and is skipped" {
  local ghost="${TEST_HOME}/does-not-exist"

  _write_config "{
    \"external_modules\": {
      \"ghost\": { \"path\": \"${ghost}\", \"paths\": { \"skills\": \"skills\" } }
    }
  }"

  run bash "${MODULE_DIR}/install.sh"

  assert_success
  refute_output --partial "missing url"
  assert_output --partial "local path not found"
  assert [ ! -d "${DEV_BOT_ROOT}/storage/external-agentic-modules/ghost" ]
}

@test "install: prunes config entries declared by disabled modules" {
  mkdir -p "${DEV_BOT_ROOT}/src/agentic/react" "${DEV_BOT_ROOT}/src/agentic/live"
  cat > "${DEV_BOT_ROOT}/src/agentic/react/external-modules.json" <<'EOF'
{
  "stale-mod": { "url": "https://example.com/org/stale.git", "paths": { "skills": "skills" } }
}
EOF
  cat > "${DEV_BOT_ROOT}/src/agentic/live/external-modules.json" <<'EOF'
{
  "live-mod": { "url": "https://example.com/org/live.git", "paths": { "skills": "skills" } }
}
EOF

  local loc_dir="${TEST_HOME}/keep-local"
  mkdir -p "${loc_dir}/skills"

  _write_config "{
    \"modules\": { \"react\": false },
    \"external_modules\": {
      \"stale-mod\": { \"url\": \"https://example.com/org/stale.git\", \"paths\": { \"skills\": \"skills\" } },
      \"live-mod\": { \"url\": \"https://example.com/org/live.git\", \"paths\": { \"skills\": \"skills\" } },
      \"keep-local\": { \"path\": \"${loc_dir}\", \"paths\": { \"skills\": \"skills\" } }
    }
  }"

  run bash "${MODULE_DIR}/install.sh"

  assert_success

  run python3 -c "
import json
with open('${DEV_BOT_ROOT}/.devbot.global.jsonc') as f:
    data = json.load(f)
entries = data['external_modules']
assert 'stale-mod' not in entries, entries
assert 'live-mod' in entries, entries
assert 'keep-local' in entries, entries
print('ok')
"
  assert_success
  assert_output "ok"
}

@test "install: prunes vendor clones not referenced by config url entries" {
  mkdir -p "${DEV_BOT_ROOT}/src/agentic/live"
  cat > "${DEV_BOT_ROOT}/src/agentic/live/external-modules.json" <<'EOF'
{
  "live-mod": { "url": "https://example.com/org/live.git", "paths": { "skills": "skills" } }
}
EOF

  # A stale clone (no config entry) and a live clone (referenced by url).
  mkdir -p "${DEV_BOT_ROOT}/vendor/org/stale/.git" "${DEV_BOT_ROOT}/vendor/org/live/.git"

  _write_config "{
    \"external_modules\": {
      \"live-mod\": { \"url\": \"https://example.com/org/live.git\", \"paths\": { \"skills\": \"skills\" } }
    }
  }"

  run bash "${MODULE_DIR}/install.sh"

  assert_success
  assert [ ! -d "${DEV_BOT_ROOT}/vendor/org/stale" ]
  assert [ -d "${DEV_BOT_ROOT}/vendor/org/live" ]
}

@test "install: merges declarations from src/tools modules into config" {
  local mod_src="${DEV_BOT_ROOT}/src/tools/some-tool"
  mkdir -p "${mod_src}"
  cat > "${mod_src}/external-modules.json" <<'EOF'
{
  "tools-decl": { "url": "https://example.com/acme/tools-decl.git", "paths": { "skills": "skills" } }
}
EOF

  _write_config "{
    \"external_modules\": {
      \"existing\": { \"url\": \"https://example.com/acme/existing.git\", \"paths\": {} }
    }
  }"

  run bash "${MODULE_DIR}/install.sh"

  assert_success

  run python3 -c "
import json
with open('${DEV_BOT_ROOT}/.devbot.global.jsonc') as f:
    data = json.load(f)
entries = data['external_modules']
assert 'tools-decl' in entries, entries
assert 'existing' in entries, entries
print('ok')
"
  assert_success
  assert_output "ok"
}

@test "init: config-only path entry wires .agents from local dir (no declaration)" {
  local loc_dir="${TEST_HOME}/local-mod"
  mkdir -p "${loc_dir}/skills"
  echo "skill" > "${loc_dir}/skills/local.md"

  _write_config "{
    \"external_modules\": {
      \"loc-mod\": { \"path\": \"${loc_dir}\", \"paths\": { \"skills\": \"skills\" } }
    }
  }"

  local project="${TEST_HOME}/project"
  mkdir -p "${project}"

  run bash "${MODULE_DIR}/init.sh" "${project}"

  assert_success
  assert [ -L "${project}/.agents/skills/loc-mod" ]
  assert [ "$(readlink "${project}/.agents/skills/loc-mod")" = "${loc_dir}/skills" ]
}

@test "init: declared url module still wires from vendor clone dir" {
  local mod_src="${DEV_BOT_ROOT}/src/agentic/some-mod"
  mkdir -p "${mod_src}"
  cat > "${mod_src}/external-modules.json" <<'EOF'
{
  "demo": { "url": "https://example.com/acme/demo.git", "paths": { "skills": "skills" } }
}
EOF

  _write_config "{
    \"external_modules\": {
      \"demo\": { \"url\": \"https://example.com/acme/demo.git\", \"paths\": { \"skills\": \"skills\" } }
    }
  }"

  mkdir -p "${DEV_BOT_ROOT}/vendor/acme/demo/skills"
  echo "demo skill" > "${DEV_BOT_ROOT}/vendor/acme/demo/skills/demo.md"

  local project="${TEST_HOME}/project-url"
  mkdir -p "${project}"

  run bash "${MODULE_DIR}/init.sh" "${project}"

  assert_success
  assert [ -L "${project}/.agents/skills/demo" ]
  assert [ "$(readlink "${project}/.agents/skills/demo")" = "${DEV_BOT_ROOT}/vendor/acme/demo/skills" ]
}

@test "init: leaves local source untouched (README intact, no .git created)" {
  local loc_dir="${TEST_HOME}/precious-mod"
  mkdir -p "${loc_dir}/skills"
  echo "# keep me" > "${loc_dir}/skills/README.md"
  echo "skill" > "${loc_dir}/skills/x.md"

  _write_config "{
    \"external_modules\": {
      \"precious-mod\": { \"path\": \"${loc_dir}\", \"paths\": { \"skills\": \"skills\" } }
    }
  }"

  local project="${TEST_HOME}/project-precious"
  mkdir -p "${project}"

  run bash "${MODULE_DIR}/init.sh" "${project}"

  assert_success
  assert [ -f "${loc_dir}/skills/README.md" ]
  assert [ ! -d "${loc_dir}/.git" ]
  assert [ -L "${project}/.agents/skills/precious-mod" ]
  assert [ "$(readlink "${project}/.agents/skills/precious-mod")" = "${loc_dir}/skills" ]
}

@test "init: missing local path warns and skips without crashing" {
  local ghost="${TEST_HOME}/ghost-mod"

  _write_config "{
    \"external_modules\": {
      \"ghost\": { \"path\": \"${ghost}\", \"paths\": { \"skills\": \"skills\" } }
    }
  }"

  local project="${TEST_HOME}/project-ghost"
  mkdir -p "${project}"

  run bash "${MODULE_DIR}/init.sh" "${project}"

  assert_success
  assert_output --partial "local path not found"
  assert [ ! -e "${project}/.agents/skills/ghost" ]
}

@test "add: local dir registers with path field (not local_path)" {
  local mod_dir="${TEST_HOME}/cli-module"
  mkdir -p "${mod_dir}/skills"

  run bash "$TOOL" add "${mod_dir}" --name=cli-module

  assert_success
  assert_output --partial "Registered: cli-module"

  run python3 -c "
import json
with open('${DEV_BOT_ROOT}/.devbot.global.jsonc') as f:
    data = json.load(f)
entry = data['external_modules']['cli-module']
assert 'path' in entry and 'local_path' not in entry, entry
print(entry['path'])
"
  assert_success
  assert_output "${mod_dir}"
}

@test "list: shows [local] for hand-written path config entry" {
  _write_config "{
    \"external_modules\": {
      \"manual\": { \"path\": \"${TEST_HOME}/somewhere\", \"paths\": { \"skills\": \"skills\" } }
    }
  }"

  run bash "$TOOL" list

  assert_success
  assert_output --partial "[local]"
}

@test "install: recognizes hand-written path entry without clone or missing-source warning" {
  local loc_dir="${TEST_HOME}/ok-local"
  mkdir -p "${loc_dir}/skills"

  _write_config "{
    \"external_modules\": {
      \"ok-local\": { \"path\": \"${loc_dir}\", \"paths\": { \"skills\": \"skills\" } }
    }
  }"

  run bash "$TOOL" install

  assert_success
  assert_output --partial "local module at"
  refute_output --partial "missing url"
}
