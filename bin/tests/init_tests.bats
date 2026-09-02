#!/usr/bin/env bats
# =============================================================================
# bin/tests/init_tests.bats
# Tests for bin/init.sh: external module init loop (Task 2) and
# memory folder linking (Task 3).
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # Resolve project root
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

  # Create a unique sandbox per test (cleaned in teardown)
  SANDBOX_DIR="$(mktemp -d)"

  command -v python3 &>/dev/null || skip "python3 not installed"
}

teardown() {
  rm -rf "${SANDBOX_DIR}" 2>/dev/null || true
}

# ── Helpers ────────────────────────────────────────────────────────────────

# _setup <json_config>
# Creates sandbox with minimal dev-bot structure for testing init functions.
_setup() {
  local json_content="${1:-{\}}"

  mkdir -p "${SANDBOX_DIR}/bin"
  mkdir -p "${SANDBOX_DIR}/src/_shared"
  mkdir -p "${SANDBOX_DIR}/src/agentic"
  mkdir -p "${SANDBOX_DIR}/src/tools"
  mkdir -p "${SANDBOX_DIR}/storage/external-agentic-modules"
  mkdir -p "${SANDBOX_DIR}/.agents/memory"

  # Minimal functions.sh
  cat > "${SANDBOX_DIR}/src/_shared/functions.sh" <<'FUNCTIONS_EOF'
#!/usr/bin/env bash
TEXT_BOLD=''; TEXT_GREEN=''; TEXT_BLUE=''; TEXT_YELLOW=''; TEXT_ORANGE=''; TEXT_RED=''; TEXT_DIM=''; TEXT_CLEAR=''
_info() { echo "INFO: $*"; }
_ok()   { echo "OK: $*"; }
_skip() { echo "SKIP: $*"; }
_warn() { echo "WARN: $*"; }
_error() { echo "ERROR: $*" >&2; exit 1; }
_fatal() { echo "FATAL: $*" >&2; exit 1; }
_log()  { echo "LOG: $*"; }
_step() { echo "STEP: $*"; }
_header_1() { echo "HEADER1: $1"; }
_header_2() { echo "HEADER2: $1"; }
_header_3() { echo "HEADER3: $*"; }
_fmt_duration() { echo "0s"; }

_devbot_get_disabled_modules() {
  local config="${DEV_BOT_ROOT}/.devbot.jsonc"
  [[ ! -f "${config}" ]] && echo "[]" && return 0
  python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    states = data.get('modules', {})
    print(json.dumps(sorted(m for m, v in states.items() if v is False)))
except:
    print('[]')
" "${config}" 2>/dev/null || echo "[]"
}

_devbot_get_project_dir() { echo ".agents"; }

_devbot_get_external_modules() {
  local config="${DEV_BOT_ROOT}/.devbot.jsonc"
  [[ ! -f "${config}" ]] && return 0
  python3 -c "
import json
try:
    with open('${config}') as f:
        data = json.load(f)
    for name in (data.get('external_modules') or {}):
        print(name)
except Exception:
    pass
" 2>/dev/null || true
}
FUNCTIONS_EOF

  # Copy init.sh (without main call)
  sed '/^main "\$@"/d' "${PROJECT_ROOT}/bin/init.sh" > "${SANDBOX_DIR}/bin/init.sh"

  # Create .devbot.jsonc
  printf '%s\n' "${json_content}" > "${SANDBOX_DIR}/.devbot.jsonc"
}

# _add_external_module <name> [init_exit_code]
# Creates an external module storage entry AND registers it in the config
# (.devbot.jsonc::modules) — the config is the source of truth.
_add_external_module() {
  local name="$1"
  local exit_code="${2:-0}"
  local dir="${SANDBOX_DIR}/storage/external-agentic-modules/${name}"
  mkdir -p "${dir}"

  cat > "${dir}/init.sh" <<EOF
#!/usr/bin/env bash
echo "${name}_init_called"
exit ${exit_code}
EOF
  chmod +x "${dir}/init.sh"

  # Create a memory subfolder
  mkdir -p "${dir}/memory"
  echo "# ${name} memory" > "${dir}/memory/note.md"

  # Register in config
  python3 -c "
import json
config = '${SANDBOX_DIR}/.devbot.jsonc'
with open(config) as f:
    data = json.load(f)
data.setdefault('external_modules', {})['${name}'] = {'url': 'https://example.com/${name}.git', 'paths': {}}
with open(config, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
"
}

# _add_orphan_storage <name> — create a storage dir with NO config entry.
_add_orphan_storage() {
  local name="$1"
  local dir="${SANDBOX_DIR}/storage/external-agentic-modules/${name}"
  mkdir -p "${dir}/memory"
  echo "# orphan" > "${dir}/memory/note.md"
}

# _run <func_name> [args...]
# Sets up env, sources files, runs the requested init function.
# Must save args before sourcing init.sh to prevent PROJECT_DIR
# from picking up leaked positional parameters.
_run() {
  local func="$1"
  shift
  local saved_args=("$@")

  export DEV_BOT_ROOT="${SANDBOX_DIR}"
  source "${SANDBOX_DIR}/src/_shared/functions.sh"
  set --
  source "${SANDBOX_DIR}/bin/init.sh"
  # Override PROJECT_DIR after init.sh sets it, so _link_memory_folders
  # creates links in the sandbox, not the cwd.
  export PROJECT_DIR="${SANDBOX_DIR}"
  "${func}" "${saved_args[@]}"
}

# ── Tests: External module init loop (Task 2) ──────────────────────────────

@test "init loop: runs init.sh from external agentic module" {
  _setup '{}'
  _add_external_module "test-ext" 0

  run _run _run_inits
  assert_success
  assert_output --partial "test-ext_init_called"
}

@test "init loop: skips external module that lacks init.sh" {
  _setup '{}'
  mkdir -p "${SANDBOX_DIR}/storage/external-agentic-modules/no-init-mod"
  # Register in config, but no init.sh present
  python3 -c "
import json
config = '${SANDBOX_DIR}/.devbot.jsonc'
with open(config) as f:
    data = json.load(f)
data.setdefault('external_modules', {})['no-init-mod'] = {'url': 'https://example.com/no-init-mod.git', 'paths': {}}
with open(config, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
"

  run _run _run_inits
  assert_success
  [[ "$output" != *"no-init-mod"* ]]
}

@test "init loop: ignores storage dirs not present in config" {
  _setup '{}'
  _add_orphan_storage "orphan-mod"
  _add_external_module "configured-mod" 0

  run _run _run_inits
  assert_success
  refute_output --partial "orphan-mod"
  assert_output --partial "configured-mod_init_called"
}

@test "init loop: external module init failure does not abort" {
  _setup '{}'
  _add_external_module "failing-ext" 1

  run _run _run_inits
  assert_success
  assert_output --partial "had issues"
}

@test "init loop: disabled_modules filtering applies to external modules" {
  _setup '{"modules": {"disabled-ext": false}}'
  _add_external_module "disabled-ext" 0
  _add_external_module "enabled-ext" 0

  run _run _run_inits
  assert_success
  assert_output --partial "disabled-ext: disabled per config"
  assert_output --partial "enabled-ext_init_called"
}

@test "init loop: multiple external modules all run" {
  _setup '{}'
  _add_external_module "ext-a" 0
  _add_external_module "ext-b" 0
  _add_external_module "ext-c" 0

  run _run _run_inits
  assert_success
  assert_output --partial "ext-a_init_called"
  assert_output --partial "ext-b_init_called"
  assert_output --partial "ext-c_init_called"
}

@test "init loop: no external modules directory is harmless" {
  _setup '{}'
  rm -rf "${SANDBOX_DIR}/storage/external-agentic-modules"

  run _run _run_inits
  assert_success
}

# ── Tests: Memory linking (Task 3) ─────────────────────────────────────────

@test "memory link: creates symlink for built-in agentic module memory" {
  _setup '{}'
  mkdir -p "${SANDBOX_DIR}/src/agentic/test-module/memory"
  echo "# test memory" > "${SANDBOX_DIR}/src/agentic/test-module/memory/test.md"

  run _run _link_memory_folders
  assert_success

  assert [ -L "${SANDBOX_DIR}/.agents/memory/test-module" ]
  assert [ "$(readlink "${SANDBOX_DIR}/.agents/memory/test-module")" = "${SANDBOX_DIR}/src/agentic/test-module/memory" ]
}

@test "memory link: creates individual file symlinks for external module memory" {
  _setup '{}'
  _add_external_module "ext-mod" 0

  run _run _link_memory_folders
  assert_success

  # External modules create individual file symlinks at the paths specified
  # in the storage structure — note.md (no module-name wrapper)
  local expected_src="${SANDBOX_DIR}/storage/external-agentic-modules/ext-mod/memory/note.md"
  assert [ -L "${SANDBOX_DIR}/.agents/memory/note.md" ]
  assert [ "$(readlink "${SANDBOX_DIR}/.agents/memory/note.md")" = "${expected_src}" ]
}

@test "memory link: skips modules without memory/ directory" {
  _setup '{}'
  mkdir -p "${SANDBOX_DIR}/src/agentic/no-memory-mod"
  mkdir -p "${SANDBOX_DIR}/src/agentic/has-memory/memory"
  echo "x" > "${SANDBOX_DIR}/src/agentic/has-memory/memory/m.md"

  run _run _link_memory_folders
  assert_success

  assert [ -L "${SANDBOX_DIR}/.agents/memory/has-memory" ]
  assert [ ! -e "${SANDBOX_DIR}/.agents/memory/no-memory-mod" ]
}

@test "memory link: idempotent — re-running does not change correct symlinks" {
  _setup '{}'
  mkdir -p "${SANDBOX_DIR}/src/agentic/mymod/memory"
  echo "x" > "${SANDBOX_DIR}/src/agentic/mymod/memory/m.md"

  run _run _link_memory_folders
  assert_success
  assert [ -L "${SANDBOX_DIR}/.agents/memory/mymod" ]

  run _run _link_memory_folders
  assert_success
  assert [ -L "${SANDBOX_DIR}/.agents/memory/mymod" ]
  assert [ "$(readlink "${SANDBOX_DIR}/.agents/memory/mymod")" = "${SANDBOX_DIR}/src/agentic/mymod/memory" ]
}

@test "memory link: built-in and external modules both linked" {
  _setup '{}'
  mkdir -p "${SANDBOX_DIR}/src/agentic/built-in-mod/memory"
  echo "b" > "${SANDBOX_DIR}/src/agentic/built-in-mod/memory/b.md"
  _add_external_module "external-mod" 0

  run _run _link_memory_folders
  assert_success

  # Built-in: dir symlink under module name
  assert [ -L "${SANDBOX_DIR}/.agents/memory/built-in-mod" ]
  # External: individual file symlinks at root (not under module name)
  assert [ -L "${SANDBOX_DIR}/.agents/memory/note.md" ]
  assert [ ! -e "${SANDBOX_DIR}/.agents/memory/external-mod" ]
}

@test "memory link: disabled_modules skips linking for disabled modules" {
  _setup '{"modules": {"disabled-mod": false}}'
  mkdir -p "${SANDBOX_DIR}/src/agentic/disabled-mod/memory"
  echo "d" > "${SANDBOX_DIR}/src/agentic/disabled-mod/memory/d.md"
  mkdir -p "${SANDBOX_DIR}/src/agentic/enabled-mod/memory"
  echo "e" > "${SANDBOX_DIR}/src/agentic/enabled-mod/memory/e.md"

  run _run _link_memory_folders
  assert_success

  assert [ ! -e "${SANDBOX_DIR}/.agents/memory/disabled-mod" ]
  assert [ -L "${SANDBOX_DIR}/.agents/memory/enabled-mod" ]
}

# ── Tests: orphaned external module pruning ────────────────────────────────

@test "prune: removes storage dirs not present in modules config" {
  _setup '{}'
  _add_orphan_storage "orphan-a"
  _add_orphan_storage "orphan-b"
  _add_external_module "keep-me" 0

  run _run _prune_orphaned_external_modules
  assert_success

  assert [ ! -e "${SANDBOX_DIR}/storage/external-agentic-modules/orphan-a" ]
  assert [ ! -e "${SANDBOX_DIR}/storage/external-agentic-modules/orphan-b" ]
  assert [ -d "${SANDBOX_DIR}/storage/external-agentic-modules/keep-me" ]
}

@test "prune: harmless when no external modules directory" {
  _setup '{}'
  rm -rf "${SANDBOX_DIR}/storage/external-agentic-modules"

  run _run _prune_orphaned_external_modules
  assert_success
}
